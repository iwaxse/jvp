struct EffectsUniform {
    intensity_smooth: f32,
    intensity_blur: f32,
    intensity_sharpen: f32,
    intensity_unsharp: f32,
    intensity_hdr: f32,
    intensity_vintage: f32,
    intensity_cyberpunk: f32,
    intensity_cleancinema: f32,
    intensity_vignette: f32,
    intensity_super_res: f32,
    intensity_deband: f32,
    intensity_bloom: f32,
    width: f32,
    height: f32,
    sharpen_type: f32,
    use_yuv: f32,
}

@group(0) @binding(0) var t_diffuse: texture_2d<f32>;
@group(0) @binding(1) var s_diffuse: sampler;
@group(0) @binding(2) var<uniform> effects: EffectsUniform;
@group(0) @binding(3) var t_uv: texture_2d<f32>;

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
}

@vertex
fn vs_main(
    @builtin(vertex_index) in_vertex_index: u32,
) -> VertexOutput {
    var out: VertexOutput;
    let x = f32(i32(in_vertex_index) / 2) * 4.0 - 1.0;
    let y = f32(i32(in_vertex_index) % 2) * 4.0 - 1.0;
    out.clip_position = vec4<f32>(x, y, 0.0, 1.0);
    out.tex_coords = vec2<f32>((x + 1.0) * 0.5, 1.0 - (y + 1.0) * 0.5);
    return out;
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn get_rgb(coords: vec2<f32>) -> vec3<f32> {
    if (effects.use_yuv > 0.5) {
        let y = textureSampleLevel(t_diffuse, s_diffuse, coords, 0.0).r;
        let uv = textureSampleLevel(t_uv, s_diffuse, coords, 0.0).rg;
        let yuv = vec3<f32>(y, uv.r, uv.g) - vec3<f32>(0.0627, 0.5, 0.5);
        return vec3<f32>(
            yuv.x * 1.164 + yuv.z * 1.793,
            yuv.x * 1.164 - yuv.y * 0.213 - yuv.z * 0.533,
            yuv.x * 1.164 + yuv.y * 2.112
        );
    } else {
        return textureSampleLevel(t_diffuse, s_diffuse, coords, 0.0).rgb;
    }
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    var color = vec4<f32>(get_rgb(in.tex_coords), 1.0);
    let texel_size = 1.0 / vec2<f32>(effects.width, effects.height);
    
    if (effects.intensity_deband > 0.01) {
        let r_val = rand(in.tex_coords);
        let angle = r_val * 6.283185;
        let dir = vec2<f32>(cos(angle), sin(angle));
        
        var avg = color.rgb;
        var count = 1.0;
        
        let range = effects.intensity_deband * 16.0;
        let threshold = (2.0 / 255.0) + effects.intensity_deband * (10.0 / 255.0);

        let offset1 = dir * range * 0.33 * texel_size;
        let s1 = get_rgb(in.tex_coords + offset1);
        if (all(abs(s1 - color.rgb) < vec3<f32>(threshold))) {
            avg += s1;
            count += 1.0;
        }

        let offset2 = dir * range * 0.66 * texel_size;
        let s2 = get_rgb(in.tex_coords - offset2);
        if (all(abs(s2 - color.rgb) < vec3<f32>(threshold))) {
            avg += s2;
            count += 1.0;
        }

        let offset3 = dir * range * 1.0 * texel_size;
        let s3 = get_rgb(in.tex_coords + offset3);
        if (all(abs(s3 - color.rgb) < vec3<f32>(threshold))) {
            avg += s3;
            count += 1.0;
        }
        
        let noise = (rand(in.tex_coords + vec2<f32>(0.1, 0.1)) - 0.5) * (1.5 / 255.0);
        color = vec4<f32>(avg / count + noise, color.a);
    }

    let original = color;

    if (effects.intensity_super_res > 0.01) {
        let e = color.rgb;
        let b = get_rgb(in.tex_coords + vec2<f32>(0.0, -texel_size.y));
        let d = get_rgb(in.tex_coords + vec2<f32>(-texel_size.x, 0.0));
        let f = get_rgb(in.tex_coords + vec2<f32>(texel_size.x, 0.0));
        let h = get_rgb(in.tex_coords + vec2<f32>(0.0, texel_size.y));

        let m_b = max(b.r, max(b.g, b.b));
        let m_d = max(d.r, max(d.g, d.b));
        let m_e = max(e.r, max(e.g, e.b));
        let m_f = max(f.r, max(f.g, f.b));
        let m_h = max(h.r, max(h.g, h.b));

        let min_l = min(m_e, min(min(m_b, m_d), min(m_f, m_h)));
        let max_l = max(m_e, max(max(m_b, m_d), max(m_f, m_h)));

        let amp = clamp(min(min_l, 2.0 - max_l) / max_l, 0.0, 1.0);
        let w = amp * (-0.125 * effects.intensity_super_res);

        let res = (b * w + d * w + f * w + h * w + e) / (4.0 * w + 1.0);
        color = vec4<f32>(clamp(res, vec3<f32>(0.0), vec3<f32>(1.0)), color.a);

        let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
        let chroma = color.rgb - luma;
        color = vec4<f32>(luma + chroma * (1.0 + effects.intensity_super_res * 0.2), color.a);
    }

    if (effects.intensity_smooth > 0.01) {
        let radius = i32(clamp(effects.intensity_smooth * 5.0, 1.0, 4.0));
        let sigma_spatial = 2.0;
        let sigma_color = mix(0.05, 0.3, effects.intensity_smooth);
        
        var filtered_color = vec3<f32>(0.0);
        var total_weight = 0.0;
        let center_color = color.rgb;

        for (var i = -radius; i <= radius; i++) {
            for (var j = -radius; j <= radius; j++) {
                let offset = vec2<f32>(f32(i), f32(j)) * texel_size;
                let sample_color = get_rgb(in.tex_coords + offset);
                let dist_sq = f32(i*i + j*j);
                let w_spatial = exp(-dist_sq / (2.0 * sigma_spatial * sigma_spatial));
                let color_diff = center_color - sample_color;
                let color_sq = dot(color_diff, color_diff);
                let w_color = exp(-color_sq / (2.0 * sigma_color * sigma_color));
                let w = w_spatial * w_color;
                filtered_color += sample_color * w;
                total_weight += w;
            }
        }
        color = vec4<f32>(filtered_color / total_weight, color.a);
    }

    if (effects.intensity_vintage > 0.01) {
        let tr = dot(color.rgb, vec3<f32>(0.393, 0.769, 0.189));
        let tg = dot(color.rgb, vec3<f32>(0.349, 0.686, 0.168));
        let tb = dot(color.rgb, vec3<f32>(0.272, 0.534, 0.131));
        color = vec4<f32>(mix(color.rgb, vec3<f32>(tr, tg, tb), effects.intensity_vintage), color.a);
    }

    if (effects.intensity_cyberpunk > 0.01) {
        let cyber = vec3<f32>(color.r * 1.5, color.g * 0.5, color.b * 1.8);
        color = vec4<f32>(mix(color.rgb, clamp(cyber, vec3<f32>(0.0), vec3<f32>(1.0)), effects.intensity_cyberpunk), color.a);
    }

    if (effects.intensity_hdr > 0.01) {
        let l = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
        var hdr = l + (color.rgb - l) * (1.0 + effects.intensity_hdr * 0.8);
        hdr = ((hdr - 0.5) * (1.0 + effects.intensity_hdr * 0.4) + 0.5);
        color = vec4<f32>(clamp(hdr, vec3<f32>(0.0), vec3<f32>(1.0)), color.a);
    }

    if (effects.intensity_cleancinema > 0.01) {
        var cine = vec3<f32>(color.r * (1.0 - 0.05 * effects.intensity_cleancinema),
                             color.g * (1.0 - 0.02 * effects.intensity_cleancinema),
                             color.b * (1.0 + 0.1 * effects.intensity_cleancinema));
        cine = ((cine - 0.5) * (1.0 + effects.intensity_cleancinema * 0.2) + 0.5);
        color = vec4<f32>(clamp(cine, vec3<f32>(0.0), vec3<f32>(1.0)), color.a);
    }

    if (effects.intensity_vignette > 0.01) {
        let dist = distance(in.tex_coords, vec2<f32>(0.5, 0.5));
        let factor = clamp(1.0 - dist * 1.414 * effects.intensity_vignette, 0.0, 1.0);
        color = vec4<f32>(color.rgb * factor, color.a);
    }

    if (effects.intensity_blur > 0.01) {
        var blur_color = vec3<f32>(0.0);
        let blur_radius = effects.intensity_blur * 3.0;
        var weight_sum = 0.0;
        for (var i = -2; i <= 2; i++) {
            for (var j = -2; j <= 2; j++) {
                let offset = vec2<f32>(f32(i), f32(j)) * texel_size * blur_radius;
                let w = exp(-(f32(i*i + j*j)) / 4.0);
                blur_color += get_rgb(in.tex_coords + offset) * w;
                weight_sum += w;
            }
        }
        color = vec4<f32>(blur_color / weight_sum, color.a);
    }

    if (effects.intensity_sharpen > 0.01) {
        if (effects.sharpen_type > 0.5) {
            let center = color.rgb;
            let up    = get_rgb(in.tex_coords + vec2<f32>(0.0, -texel_size.y));
            let down  = get_rgb(in.tex_coords + vec2<f32>(0.0, texel_size.y));
            let left  = get_rgb(in.tex_coords + vec2<f32>(-texel_size.x, 0.0));
            let right = get_rgb(in.tex_coords + vec2<f32>(texel_size.x, 0.0));
            let up_left    = get_rgb(in.tex_coords + vec2<f32>(-texel_size.x, -texel_size.y));
            let up_right   = get_rgb(in.tex_coords + vec2<f32>(texel_size.x, -texel_size.y));
            let down_left  = get_rgb(in.tex_coords + vec2<f32>(-texel_size.x, texel_size.y));
            let down_right = get_rgb(in.tex_coords + vec2<f32>(texel_size.x, texel_size.y));
            let edges = (center * 8.0) - (up + down + left + right + up_left + up_right + down_left + down_right);
            let sharpened = center + edges * effects.intensity_sharpen * 0.5;
            color = vec4<f32>(clamp(sharpened, vec3<f32>(0.0), vec3<f32>(1.0)), color.a);
        } else {
            let e = color.rgb;
            let b = get_rgb(in.tex_coords + vec2<f32>(0.0, -texel_size.y));
            let d = get_rgb(in.tex_coords + vec2<f32>(-texel_size.x, 0.0));
            let f = get_rgb(in.tex_coords + vec2<f32>(texel_size.x, 0.0));
            let h = get_rgb(in.tex_coords + vec2<f32>(0.0, texel_size.y));
            let min_rgb = min(min(min(b, d), min(e, f)), h);
            let max_rgb = max(max(max(b, d), max(e, f)), h);
            let limit = min(min_rgb, 1.0 - max_rgb);
            let max_max = max(max_rgb, vec3<f32>(0.00001)); 
            let sharpness = mix(-0.125, -0.2, effects.intensity_sharpen);
            var w = (limit / max_max) * sharpness;
            let res = (b * w + d * w + f * w + h * w + e) / (4.0 * w + 1.0);
            color = vec4<f32>(clamp(res, vec3<f32>(0.0), vec3<f32>(1.0)), color.a);
        }
    }

    if (effects.intensity_unsharp > 0.01) {
        var blurred = vec3<f32>(0.0);
        var w_sum = 0.0;
        for (var i = -2; i <= 2; i++) {
            for (var j = -2; j <= 2; j++) {
                let offset = vec2<f32>(f32(i), f32(j)) * texel_size * 0.6;
                let w = exp(-(f32(i*i + j*j)) / 1.0);
                blurred += get_rgb(in.tex_coords + offset) * w;
                w_sum += w;
            }
        }
        blurred = blurred / w_sum;
        let diff = color.rgb - blurred;
        let weight = smoothstep(vec3<f32>(0.01), vec3<f32>(0.06), abs(diff));
        let high_freq = diff * weight;
        let unsharped = color.rgb + high_freq * effects.intensity_unsharp * 3.0;
        color = vec4<f32>(clamp(unsharped, vec3<f32>(0.0), vec3<f32>(1.0)), color.a);
    }

    if (effects.intensity_bloom > 0.01) {
        var bloom_sum = vec3<f32>(0.0);
        let threshold = 0.92;
        let soft_knee = 0.05;
        let bloom_radius = effects.intensity_bloom * 12.0;
        
        for (var i = -3; i <= 3; i++) {
            for (var j = -3; j <= 3; j++) {
                let offset = vec2<f32>(f32(i), f32(j)) * texel_size * bloom_radius;
                let b_sample = get_rgb(in.tex_coords + offset);
                let b_brightness = dot(b_sample, vec3<f32>(0.299, 0.587, 0.114));
                
                let weight = exp(-(f32(i*i + j*j)) / 9.0);
                let soft_thr = smoothstep(threshold - soft_knee, threshold + soft_knee, b_brightness);
                bloom_sum += b_sample * weight * soft_thr;
            }
        }
        let bloom_strength = effects.intensity_bloom * effects.intensity_bloom * 0.1;
        color = vec4<f32>(color.rgb + bloom_sum * bloom_strength, color.a);
    }

    return vec4<f32>(color.rgb, 1.0);
}
