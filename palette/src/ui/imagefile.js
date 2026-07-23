// Decode an image at the browser edge into an RGB `Raster`.
//
// `src/core/` may not touch the DOM, so PNG/JPEG decoding happens here through `Image` +
// canvas and hands core a plain pixel buffer. Shared by the recolour gallery (stills) and
// the "Fit to image" control, so there is one decode path rather than two.

import { Raster } from '../core/raster.js';

/** Decode PNG/JPEG bytes through the browser and hand back an RGB `Raster`. */
export function decodeStillToRaster(bytes, name = 'image') {
  return new Promise((resolvePromise, reject) => {
    const url = URL.createObjectURL(new Blob([bytes]));
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const { data } = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const raster = new Raster(canvas.width, canvas.height, null);
      for (let i = 0, p = 0; i < data.length; i += 4, p += 3) {
        raster.data[p] = data[i];
        raster.data[p + 1] = data[i + 1];
        raster.data[p + 2] = data[i + 2];
      }
      URL.revokeObjectURL(url);
      resolvePromise(raster);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error(`could not decode ${name}`));
    };
    img.src = url;
  });
}
