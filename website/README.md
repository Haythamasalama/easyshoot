# EasyShoot website

A single static page (`index.html`) in five languages (English, Arabic with right-to-left layout, French, Spanish and German). It has no build step: open the file in a browser to preview it.

- **Deploy:** `.github/workflows/website.yml` publishes this folder to GitHub Pages on every push to `main` that changes `website/`. Turn it on once in **Settings → Pages → Source: GitHub Actions**. The site lives at <https://easyshoot.haythamasalama.me>; `CNAME` holds the custom domain.
- **Download button:** points to the latest GitHub Release. Push a tag such as `v1.0.0` and `.github/workflows/release.yml` builds the app and attaches `EasyShoot.zip`.
- **Translations:** stored in the `I18N` object at the bottom of `index.html`. English text lives in the HTML itself.
