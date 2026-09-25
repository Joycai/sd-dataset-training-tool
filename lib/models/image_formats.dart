/// Image file extensions the app treats as dataset images, lowercased with a
/// leading dot. A caption type can never claim one of these — see
/// `normalizeCaptionExtension`.
const Set<String> supportedImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.bmp',
  '.webp',
};
