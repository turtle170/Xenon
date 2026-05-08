use image::GenericImageView;

pub fn generate_ascii(path: &str, width: u32) -> String {
    let img = match image::open(path) {
        Ok(img) => img,
        Err(_) => return "Dragon Icon Not Found".to_string(),
    };

    let (original_width, original_height) = img.dimensions();
    let aspect_ratio = original_height as f32 / original_width as f32;
    let height = (width as f32 * aspect_ratio * 0.5) as u32; // 0.5 to compensate for char height

    let img = img.resize_exact(width, height, image::imageops::FilterType::Nearest);
    let chars = [" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"];

    let mut ascii = String::new();
    for y in 0..height {
        for x in 0..width {
            let pixel = img.get_pixel(x, y);
            let brightness = (pixel[0] as f32 * 0.299 + pixel[1] as f32 * 0.587 + pixel[2] as f32 * 0.114) as u8;
            let index = (brightness as usize * (chars.len() - 1)) / 255;
            ascii.push_str(chars[index]);
        }
        ascii.push('\n');
    }
    ascii
}
