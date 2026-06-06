/*
 * jvp (Jamy-chan Video Player)
 * Copyright (C) 2026 iwaxse
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

use crate::domain::video::MediaFileEntry;
use ignore::WalkBuilder;
use ignore::WalkState;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread::available_parallelism;

static MEDIA_SEARCH_ROOTS: Lazy<Mutex<Vec<String>>> = Lazy::new(|| Mutex::new(load_roots()));

const CONFIG_DIR_NAME: &str = "jvp";
const CONFIG_FILE_NAME: &str = "media_roots.json";

#[derive(Debug, Serialize, Deserialize)]
struct RootsConfig {
    roots: Vec<String>,
}

fn config_dir() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(env::temp_dir)
        .join("Library")
        .join("Application Support")
        .join(CONFIG_DIR_NAME)
}

fn config_path() -> PathBuf {
    config_dir().join(CONFIG_FILE_NAME)
}

fn normalize_roots(roots: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    roots
        .into_iter()
        .filter_map(|root| {
            let trimmed = root.trim();
            if trimmed.is_empty() {
                return None;
            }
            let path = PathBuf::from(trimmed);
            if !path.is_dir() {
                return None;
            }
            let key = path.to_string_lossy().to_string();
            if seen.insert(key.clone()) {
                Some(key)
            } else {
                None
            }
        })
        .collect()
}

fn default_roots() -> Vec<String> {
    env::current_dir()
        .ok()
        .map(|dir| vec![dir.to_string_lossy().to_string()])
        .unwrap_or_else(|| vec![".".to_string()])
}

fn load_roots() -> Vec<String> {
    let path = config_path();
    let loaded = fs::read_to_string(path)
        .ok()
        .and_then(|content| serde_json::from_str::<RootsConfig>(&content).ok())
        .map(|config| normalize_roots(config.roots))
        .unwrap_or_default();

    if loaded.is_empty() {
        default_roots()
    } else {
        loaded
    }
}

fn save_roots(roots: &[String]) -> Result<(), String> {
    let dir = config_dir();
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let payload = RootsConfig {
        roots: roots.to_vec(),
    };
    let json = serde_json::to_string_pretty(&payload).map_err(|e| e.to_string())?;
    fs::write(config_path(), json).map_err(|e| e.to_string())
}

fn is_supported_media_file(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| {
            matches!(
                ext.to_ascii_lowercase().as_str(),
                "mp4"
                    | "m4v"
                    | "mov"
                    | "mkv"
                    | "webm"
                    | "avi"
                    | "flv"
                    | "ts"
                    | "m2ts"
                    | "mts"
                    | "mpg"
                    | "mpeg"
                    | "wmv"
                    | "gif"
            )
        })
        .unwrap_or(false)
}

fn to_entry(path: &Path) -> Option<MediaFileEntry> {
    let display_name = path.file_name()?.to_string_lossy().to_string();
    let directory_path = path
        .parent()
        .unwrap_or_else(|| Path::new(""))
        .to_string_lossy()
        .to_string();

    Some(MediaFileEntry {
        path: path.to_string_lossy().to_string(),
        display_name,
        directory_path,
    })
}

pub fn get_media_search_roots() -> Vec<String> {
    MEDIA_SEARCH_ROOTS
        .lock()
        .ok()
        .map(|roots| roots.clone())
        .unwrap_or_default()
}

pub fn init_media_search_roots() {
    let _ = Lazy::force(&MEDIA_SEARCH_ROOTS);
}

pub fn set_media_search_roots(roots: Vec<String>) -> Result<(), String> {
    let normalized = normalize_roots(roots);
    save_roots(&normalized)?;
    if let Ok(mut lock) = MEDIA_SEARCH_ROOTS.lock() {
        *lock = normalized;
    }
    Ok(())
}

pub fn scan_media_files() -> Vec<MediaFileEntry> {
    let roots = get_media_search_roots();
    let threads = available_parallelism().map(|n| n.get()).unwrap_or(4);
    let files = Arc::new(Mutex::new(Vec::new()));
    let seen = Arc::new(Mutex::new(HashSet::new()));

    if roots.is_empty() {
        return Vec::new();
    }

    let mut builder = WalkBuilder::new(&roots[0]);
    for root in roots.iter().skip(1) {
        builder.add(root);
    }
    builder
        .hidden(false)
        .git_ignore(false)
        .git_global(false)
        .git_exclude(false)
        .follow_links(true)
        .threads(threads);

    let files = Arc::clone(&files);
    let seen = Arc::clone(&seen);

    builder.build_parallel().run(|| {
        let files = Arc::clone(&files);
        let seen = Arc::clone(&seen);
        Box::new(move |result| {
            if let Ok(entry) = result {
                if entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
                    let path = entry.path().to_path_buf();
                    if is_supported_media_file(&path) {
                        let key = path.to_string_lossy().to_string();
                        let mut seen_lock = seen.lock().unwrap();
                        if seen_lock.insert(key) {
                            if let Some(media) = to_entry(&path) {
                                files.lock().unwrap().push(media);
                            }
                        }
                    }
                }
            }
            WalkState::Continue
        })
    });

    let mut files = match Arc::try_unwrap(files) {
        Ok(mutex) => mutex.into_inner().unwrap_or_default(),
        Err(arc) => arc.lock().unwrap().clone(),
    };

    files.sort_by(|a, b| {
        a.display_name
            .to_lowercase()
            .cmp(&b.display_name.to_lowercase())
            .then_with(|| a.path.cmp(&b.path))
    });

    files
}
