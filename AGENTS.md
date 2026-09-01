# AGENTS.md

> **Tek kaynak (single source of truth).** Tüm ajan talimatları bu dosyada tutulur.
> `CLAUDE.md` bu dosyayı `@AGENTS.md` ile import eder; bu yüzden ikisi her zaman senkrondur.
> Değişiklikleri **yalnızca bu dosyada** yap.

## Proje

- **Ad:** launchpad
- **Amaç:** pons (`pons.family`) benzeri, fixed-supply token launchpad. Bonding
  curve → graduation → kilitli likidite. EVM zinciri (Robinhood Chain, doğrulanacak).
  Bölümler: Explore (Graduated + Explore listeleri), coin detay + trade + grafik,
  Forum (Memestock), Analytics (kendi indexer), Docs. Non-custodial.
- **Detaylı özellik analizi:** `notes.md`
- **Dizin:** `C:\Users\mesut\Desktop\workspace\A-projects\launchpad`

## Kurulum

```bash
# doldurulacak
```

## Sık kullanılan komutlar

| Amaç | Komut |
|------|-------|
| Kur  | _(doldurulacak)_ |
| Çalıştır | _(doldurulacak)_ |
| Test | _(doldurulacak)_ |
| Lint | _(doldurulacak)_ |
| Build | _(doldurulacak)_ |

## Kod standartları

- _(doldurulacak)_

## Yapma / Dikkat

- _(doldurulacak)_

## Çalışma pratiği — Backlog & limit yönetimi

- Yarım kalan her iş `backlog.md` → "Aktif" bölümüne yazılır (sebep: zaman /
  limit / kapsam kararı). Şablon dosyanın içinde.
- **Kullanım limitleri ~%90-92'ye yaklaştığında:**
  1. Yeni veya yarım işe limit yetersizliğiyle devam etme.
  2. Mevcut durumu `backlog.md`'ye net yaz: dosyalar, tam duruş noktası,
     sıradaki somut adım.
  3. Kullanıcıya haber ver: "Limit ~%X, işi backlog'a aldım."
- **Not:** Kullanım limiti yüzdesi otomatik ölçülemez. Tetikleyiciler:
  kullanıcının uyarması, ya da bağlamın özetlenmeye başlaması gibi belirtiler.
  Kullanıcı bir yüzde söylerse ona göre davran.

## Senkronizasyon kuralı

- `AGENTS.md` = içeriğin bulunduğu tek dosya.
- `CLAUDE.md` yalnızca `@AGENTS.md` satırını içerir; kendi başına içerik barındırmaz.
- Bir talimat eklemek/değiştirmek: **sadece `AGENTS.md`** düzenle. `CLAUDE.md`'ye dokunma.
