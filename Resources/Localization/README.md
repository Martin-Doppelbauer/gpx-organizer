# Texts per language

One folder per language: `en.lproj`, `de.lproj`, later `fr.lproj`, `it.lproj`, `es.lproj`, `pt-BR.lproj`.

- `Localizable.strings` holds the texts of the program. **The English text is the key**: `"Reset Colors" = "Farben zurücksetzen";`.
  A text that is missing in a language is shown in English.
- `README.md` and `UserGuide.md` inside a folder are the help texts in that language (the Help menu opens the one that matches;
  without one it shows the English files from the project root).
- Texts with placeholders keep them: `%@` (text), `%d` (whole number), `%.1f` (number with a decimal).

In the code: SwiftUI literals (`Text("…")`, `Button("…")`, `Toggle("…")`) are found automatically; everything else uses `L("…")`
(for example menu items, alerts and status lines). `build_app.sh` copies every `*.lproj` folder into the program and lists the
languages in `Info.plist`. The language can be chosen in Settings → General → Language (takes effect at the next start).
