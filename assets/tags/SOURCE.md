# Tag dictionary sources

## `wd_tags.csv` (bundled)

Verbatim copy of `selected_tags.csv` from
[SmilingWolf/wd-swinv2-tagger-v3](https://huggingface.co/SmilingWolf/wd-swinv2-tagger-v3)
(Apache-2.0). Columns: `tag_id,name,category,count`.

This file is the tagger's own label set, which is why it is the one bundled:
every tag it can complete is a tag the AI tagger can also produce, so the two
never disagree on spelling. Category `9` rows are the model's rating outputs
(`general` / `sensitive` / `questionable` / `explicit`), not danbooru tags —
`TagDictionaryService` drops them on parse.

To refresh:

```sh
curl -sSL -o assets/tags/wd_tags.csv \
  https://huggingface.co/SmilingWolf/wd-swinv2-tagger-v3/resolve/main/selected_tags.csv
```

## `danbooru.csv` (downloaded on demand, not in this repo)

Fetched at runtime into `<app-support>/tags/` from
[DominikDoom/a1111-sd-webui-tagcomplete](https://github.com/DominikDoom/a1111-sd-webui-tagcomplete)
(MIT). Columns: `name,category,count,"aliases"` — top 100k danbooru tags by
post count, with aliases and the artist/copyright/meta categories the WD label
file does not carry.

Deliberately not vendored: it is ~3.5 MB of third-party data that only some
users need, and keeping it out of the repo means it can be re-fetched fresher
than a checked-in snapshot would be.
