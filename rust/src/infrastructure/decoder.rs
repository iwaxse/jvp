use anyhow::{anyhow, Result};
use std::ffi::{c_void, CString};
use std::os::raw::c_char;

extern "C" {
    fn jvp_player_open(id: i64, path: *const c_char) -> i32;
    fn jvp_player_get_metadata(
        id: i64,
        width: *mut i32,
        height: *mut i32,
        duration: *mut f64,
        fps: *mut f64,
    );
    fn jvp_player_play(id: i64);
    fn jvp_player_pause(id: i64);
    fn jvp_player_seek(id: i64, time_sec: f64, accurate: i32);
    fn jvp_player_set_volume(id: i64, vol: f32);
    fn jvp_player_get_pts(id: i64) -> f64;
    fn jvp_player_copy_pixel_buffer(id: i64) -> *mut c_void;
    fn jvp_player_is_completed(id: i64) -> i32;
    fn jvp_player_get_thumbnail(
        id: i64,
        time_sec: f64,
        out_width: *mut i32,
        out_height: *mut i32,
        out_size: *mut i32,
    ) -> *mut u8;
    fn jvp_player_free_thumbnail_buffer(buffer: *mut u8, size: i32);
    fn jvp_player_register_render_callback(callback: extern "C" fn());
    fn jvp_player_register_update_input_callback(callback: extern "C" fn(*mut c_void));
    fn jvp_player_register_set_output_callback(callback: extern "C" fn(*mut c_void, i32, i32));
}

pub struct VideoDecoder {
    pub texture_id: i64,
    pub width: u32,
    pub height: u32,
    pub duration_secs: f64,
    pub frame_rate: f64,
    pub current_pts: f64,
    pub hw_accel: bool,
}

unsafe impl Send for VideoDecoder {}
unsafe impl Sync for VideoDecoder {}

impl VideoDecoder {
    pub fn new(path: &str, _enable_hw: bool) -> Result<Self> {
        let c_path = CString::new(path).map_err(|e| anyhow!("Invalid path: {}", e))?;
        let dummy_id: i64 = -1;

        let success = unsafe { jvp_player_open(dummy_id, c_path.as_ptr()) };
        if success == 0 {
            return Err(anyhow!("Failed to open video via AVPlayer"));
        }

        unsafe {
            jvp_player_register_render_callback(crate::api::simple::jvp_render_frame);
            jvp_player_register_update_input_callback(
                crate::api::simple::jvp_player_update_input_cv_buffer,
            );
            jvp_player_register_set_output_callback(
                crate::api::simple::jvp_player_set_output_texture,
            );
        }

        let mut w: i32 = 0;
        let mut h: i32 = 0;
        let mut duration: f64 = 0.0;
        let mut fps: f64 = 30.0;

        unsafe {
            jvp_player_get_metadata(dummy_id, &mut w, &mut h, &mut duration, &mut fps);
        }

        Ok(Self {
            texture_id: dummy_id,
            width: w as u32,
            height: h as u32,
            duration_secs: duration,
            frame_rate: fps,
            current_pts: 0.0,
            hw_accel: true,
        })
    }

    pub fn set_texture_id(&mut self, id: i64) {
        self.texture_id = id;
    }

    pub fn play(&self) {
        unsafe { jvp_player_play(self.texture_id) };
    }

    pub fn pause(&self) {
        unsafe { jvp_player_pause(self.texture_id) };
    }

    pub fn set_volume(&self, vol: f32) {
        unsafe { jvp_player_set_volume(self.texture_id, vol) };
    }

    pub fn seek(&mut self, time_sec: f64, accurate: bool) -> Result<()> {
        let acc = if accurate { 1 } else { 0 };
        unsafe { jvp_player_seek(self.texture_id, time_sec, acc) };
        self.current_pts = time_sec;
        Ok(())
    }

    pub fn next_frame(&mut self) -> Result<Option<f64>> {
        let pts = unsafe { jvp_player_get_pts(self.texture_id) };
        self.current_pts = pts;

        let completed = unsafe { jvp_player_is_completed(self.texture_id) } != 0;
        if completed {
            return Ok(None);
        }
        Ok(Some(pts))
    }

    pub fn get_cv_pixel_buffer(&self) -> Option<*mut c_void> {
        let ptr = unsafe { jvp_player_copy_pixel_buffer(self.texture_id) };
        if ptr.is_null() {
            None
        } else {
            Some(ptr)
        }
    }

    pub fn get_scaled_rgba(
        &self,
        time_sec: f64,
        _target_width: u32,
        _target_height: u32,
    ) -> Result<(Vec<u8>, u32, u32)> {
        let mut w: i32 = 0;
        let mut h: i32 = 0;
        let mut size: i32 = 0;
        let ptr = unsafe {
            jvp_player_get_thumbnail(self.texture_id, time_sec, &mut w, &mut h, &mut size)
        };
        if ptr.is_null() {
            return Err(anyhow!("Failed to generate thumbnail via Swift"));
        }
        let data = unsafe { std::slice::from_raw_parts(ptr, size as usize) }.to_vec();
        unsafe {
            jvp_player_free_thumbnail_buffer(ptr, size);
        }
        Ok((data, w as u32, h as u32))
    }
}
