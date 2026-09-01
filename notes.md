# Notes — launchpad

> Proje hakkında serbest notlar: fikirler, kararlar, açık sorular, araştırma
> çıktıları. Yarım işler `backlog.md`'ye; kalıcı ajan talimatları `AGENTS.md`'ye.

---

## Referans ürün

- **pons** (Pons Labs, LLC) — `pons.family` / `@ponsdotfamily`
- Fixed-supply token launchpad, **Robinhood Chain** üzerinde (EVM L2).
- Model: bonding curve → belirli eşikte "graduation" → likidite kilitli havuz.
- Non-custodial: "Your wallet submits every transaction. pons does not custody assets."
- Public analytics'i **Dune** verisiyle besliyor ("Data is supplied by Dune").
- Wallet UX'i **Reown** ile ("UX by reown").
- Biz pons-benzeri bir ürün kuracağız; aşağıdaki ekranlar referans alınacak.

---

## Özellik analizi (ekran ekran)

### 1. Navbar (Image #4)
- Sol: logo (P işareti).
- Orta: segment kontrol — **Explore / Forum / Analytics**.
- Sağ: tema toggle (güneş ikonu, light/dark), **Connect** butonu (lime yeşil pill).
- Koyu tema varsayılan.

### 2. Wallet bağlama (Image #5)
- "Connect Wallet" modalı. Liste: WalletConnect (QR CODE etiketi), Trust Wallet,
  MetaMask, Binance Wallet, SafePal, en altta "Search Wallet — 540+".
- pons burada **Reown** (eski WalletConnect / Web3Modal) kullanıyor.
- **Bizim seçeneklerimiz** → aşağıdaki "Teknik kararlar / Wallet connect".

### 3. Token launch (Image #6)
- Üst sağda **v2 / v1** toggle (iki farklı launch motoru/kontratı).
- Sol form alanları:
  - Name, Ticker
  - Description (kısa metin)
  - Token image (yükleme)
  - X profile (`x.com/handle`), Telegram (`t.me/community`)
  - **Paired asset** dropdown (ETH) — "Graduates once the curve raises 4.2 ETH."
  - **Developer buy** — launch anında geliştiricinin alacağı miktar (ETH), bakiye kontrolü
  - **Advanced** (açılır) — ek ayarlar
  - Alt: "ETH pair, ETH 0.0005 due" + **Connect wallet** CTA
- Sağ **canlı önizleme kartı** ("Your token"):
  - Launch fee **0.0005 ETH**
  - Paired with **ETH**
  - Trade fee **1.00%**
  - Launch window **99% snipe tax, 3s** (ilk 3 sn agresif anti-snipe vergisi)
  - Graduation **4.2 ETH**
  - Liquidity **Locked**
- Not: bu parametreler (fee, snipe tax süresi, graduation eşiği) muhtemelen
  v1 ve v2 arasında farklı; config'ten gelmeli.

### 4. Arama & filtre modalı — "Stocks" (Image #7)
- Arama input: name / ticker / address.
- **Sort by:** Relevance, Market cap, Volume, Newest, Oldest.
- **Age:** All / 24h / 7d.
- **Pair** filtresi: All / **Stocks** / tek tek hisse ticker chip'leri
  (AAPL, AMD, AMZN, BB, COIN, COST, CRCL, DJT, GLD, GME, GOOGL, HIMS, META,
  MSFT, MSTR, MU, NVDA, PLTR, QQQ, RDDT, SNDK, SPCX, SPY, TSLA, TTWO).
  → "Stocks" butonu = token'ın eşleştiği (paired) varlık bir hisse token'ı.
- Sonuç satırı: ikon, isim, $TICKER · $MC · yaş.
- Sayfalama: "1 to 24 of 17,302 · 1 / 721 · Previous / Next".

### 5. Listeler — Graduated & Explore (Image #8)
- **Graduated** (rozet + sayı, ör. 510): "Tokens that cleared the graduation threshold."
  - 5'li kart grid. Kart: görsel, "Graduated" rozeti (+ bazılarında "V2" rozeti),
    isim, $TICKER, **MC / FDV**, kısa kontrat adresi, yaş ("49d ago").
  - Sayfalama 1..51.
- **Explore** (ör. 410,337 launched): "Tokens still climbing toward graduation on Robinhood Chain."
  - Filtreler: Recent buys / Newest / Oldest / Market cap / Volume · All/24h/7d · **Both / v1 / v2**.
  - Aynı kart yapısı.

### 6. Coin detay + grafik (Image #9)
- **About** kutusu: kısa açıklama; "Burned 0 DELTA · $0 · 0% of supply".
  Linkler: X, **Dexscreener**, **GeckoTerminal**, **Contract**, **Pool**.
- **Sol trade paneli:**
  - Token başlığı + tabs **Market / Limit / Orders**
  - **Sell** input (varlık dropdown, ör. ETH) ↕ **Buy** input (token)
  - Hızlı oran butonları: 25% / 50% / 75% / 100%
  - **Slippage** 1% + Adjust
  - **Connect wallet** CTA
- **Sağ üst istatistik şeridi:** Market cap, Liquidity, 24h volume, ATH.
- **Fiyat başlığı:** büyük değer + değişim % + zaman dilimi (1H).
- **Grafik:** area chart; **Heatmap** toggle; zaman dilimleri **5M / 1H / 6H / 1D / ALL**;
  X ekseni saat etiketleri.

### 7. Recent trades & Holders (Image #10)
- Tabs: **Recent trades / Holders**. Sağda adet ("50").
- Trade satırı: yön oku (yeşil ↗ buy / kırmızı ↙ sell), miktar + TICKER,
  kısa cüzdan adresi, fiyat (ETH) + $ karşılığı, "Xm" (kaç dk önce).
- Sayfalama 1..5.
- Holders tab: (muhtemelen) adres, bakiye, % supply, ilk alım tarihi.

### 8. Forum — "Memestock" (Image #13)
- **Üstte kayan şerit (ticker tape):** genel piyasa verileri — hisse fiyatları
  (SPCX, GOOGL, TSLA, GME, AAPL, SPY, SNDK...) + günlük değişim %. Sürekli sağdan
  sola akıyor.
- Başlık: "Memestock — Every launch with a community, ranked by what is moving."
- Tabs: **Hot / New / Top**.
- Gönderi akışı (reddit tarzı): `s/TICKER` community, upvote/downvote,
  kullanıcı adı + kısa adres + zaman, başlık, gövde metni/görsel,
  yorum sayısı, **Buy** butonu (satır içi).
- Sağ sidebar: **"Biggest launches"** — arama + 1–10 sıralı liste (`s/PONS $444M` ...)
  + "Browse the launchpad" linki.
- Bizde: şerit = genel piyasa verisi; akış = **sadece kendi coinlerimizle ilgili** mesajlar.

### 9. Analytics — "Protocol analytics" (Image #12)
- "Independent onchain reporting for pons markets on Robinhood Chain."
- Toggle **24h / All time**. "View on Dune" butonu. "Dune updated HH:MM, latest complete day ... UTC".
- Stat tiles: **24h volume** ($457.13M, ±% prior day), **24h launches** (17.9K, ±%),
  **24h trades** (0, "No prior-day baseline").
- Grafikler: **Trading volume** (günlük bar), **Token launches** (günlük bar);
  son tamamlanmış gün vurgulu.
- pons bunu Dune'dan çekiyor. **Biz kendimiz indexleyeceğiz** → "Teknik kararlar / Analytics".

### 10. Docs (Image #11'de footer linki)
- Kapsamlı hazırlanacak. Muhtemel bölümler: Nasıl çalışır (bonding curve,
  graduation, fees, snipe tax), v1 vs v2 farkları, token launch rehberi,
  trading (slippage, limit orders), likidite & kilit, kontrat adresleri &
  ABI'ler, API/indexer dokümanı, güvenlik/risk, SSS.

### 11. Footer (Image #11)
- Logo + tanım: "Launch and explore fixed-supply tokens on Robinhood Chain.
  Your wallet submits every transaction. [brand] does not custody assets."
- Kolonlar: **Product** (Explore, Analytics, Create, Profile, Docs) ·
  **Legal** (Privacy Policy, Terms of Use) · **Risk notice** (işlemler geri
  alınamaz, tokenlar değer kaybedebilir, custody/garanti/finansal tavsiye yok).
- Alt: © yıl + şirket; X linki.

---

## Teknik kararlar

### Wallet connect — seçenekler
pons "UX by reown" kullanıyor. EVM zinciri olduğu için bizim alternatiflerimiz:

| Kütüphane | Ne | Maliyet | Not |
|-----------|-----|---------|-----|
| **Reown AppKit** (eski Web3Modal/WalletConnect) | 540+ cüzdan, mobil QR, en geniş kapsama | Ücretsiz; `cloud.reown.com`'dan project ID | pons ile birebir aynı deneyim |
| **RainbowKit** (+ wagmi + viem) | Temiz UX, dev-dostu, çok yaygın | Tamamen ücretsiz, açık kaynak | EVM launchpad için sağlam varsayılan |
| **ConnectKit** (family) | RainbowKit'e benzer, sade | Ücretsiz | Alternatif |
| **Dynamic / Privy** | Embedded wallet + email/Google/sosyal login | Ücretsiz tier + ücretli | Kripto-yerlisi olmayan onboarding istersen |
| **thirdweb Connect** | Modal + embedded + hesap soyutlama | Ücretsiz tier | thirdweb ekosistemine bağlar |
| **Web3-Onboard** (Blocknative) | Framework-agnostik | Ücretsiz | React dışı stack için |

- **Öneri:** temel altyapı **wagmi + viem**. Modal için ya **RainbowKit** (ücretsiz,
  devasa benimseme) ya da pons'u birebir istiyorsak **Reown AppKit** (en geniş
  cüzdan listesi hazır gelir). Sonradan email/sosyal onboarding gerekirse
  **Privy** veya **Dynamic** eklenir.
- Karar bekliyor: bkz. Açık sorular.

### Analytics — kendi indexer'ımız
pons Dune kullanıyor; biz kendimiz yapacağız. Seçenekler:

| Yaklaşım | Ne | Maliyet | Not |
|----------|-----|---------|-----|
| **Ponder** (`ponder.sh`) | TypeScript indexer, self-host, Postgres'e yazar, GraphQL/SQL API | Ucuz: 1 küçük VPS + RPC planı | DX subgraph'tan çok daha basit; tek ekip uygulaması için ideal |
| **The Graph subgraph** (decentralized) | Standart, kompozalanabilir | Query fee (GRT) + signal; hacimde pahalılaşır | Hosted service kapandı |
| **Self-host Graph Node** | Subgraph'ı kendi sunucunda | Query fee yok ama infra sen (Postgres + IPFS + archive node) | Ağır operasyon |
| **Envio HyperIndex** | Çok hızlı, multi-chain, hosted/self-host | Cömert ücretsiz tier | Hızlı backfill |
| **Subsquid / SQD** | Yüksek throughput | Orta | Ağır tarihsel veri |
| **Goldsky** | Managed subgraph + mirror pipeline | Ücretli, düşük operasyon | Kolaycı yol |
| **Custom** (viem `watchEvent`/log polling + Postgres + cron aggregation) | Tam kontrol | En ucuz altyapı, en çok emek | |
| **Dune API** | pons'un yaptığı; SQL + embed | Ücretsiz-orta | Sadece harici çapraz-kontrol olarak |

- **Öneri:** **Ponder** self-host. Kontrat event'lerini (launch, buy, sell,
  graduate) indexle → Postgres → materialized view / cron ile günlük agregasyon
  (volume, launches, trades) → kendi API'mizden frontend grafiklerine besle.
- Kabaca maliyet: ~$20–40/ay VPS + RPC (Alchemy/QuickNode ücretsiz–~$50/ay,
  hacme göre) + Postgres ($0 self-host – ~$25/ay managed). Graph query fee'lerinden
  ölçekte çok daha ucuz.
- Subgraph sadece "decentralized / 3. parti entegrasyonu bize subgraph üzerinden
  bağlansın" senaryosu gerekirse.
- Fiyat grafikleri için ayrıca OHLC candle tablosu üretmek gerekecek (trade
  event'lerinden zaman kovalarına toplama).

---

## Fikirler

-

## Kararlar

- **2026-09-01 — Wallet: Privy.** Embedded wallet + email/sosyal login + harici
  cüzdan bağlama; altta wagmi/viem. Sebep: kripto-yerlisi olmayan onboarding.
  RainbowKit / Reown AppKit elendi.
- **2026-09-01 — Chart: TradingView Lightweight Charts** (ücretsiz). Charting
  Library (lisanslı, ağır) ve Advanced widget (yalnız borsa-listeli tokenlarda
  çalışır) elendi. Datafeed'i kendi indexer'ımız besler; area+gradient görünüm
  zaten kütüphanenin doğal stili.
- **2026-09-01 — Analytics: Dune bağımlılığı yok.** Kendi indexer'ımızdan günlük
  aggregate üretilir (gerçek zamanlı + dış servise bağımsız).
- **2026-09-01 — Backend dili: Go (kesin).** tRPC YOK. Ponder YOK (TS olduğu için).
  Indexer = kendi Go servisimiz (`go-ethereum` ethclient + `abigen` binding +
  Postgres). Monorepo. DB = Docker Postgres (dev). Hosting şimdilik konu dışı.
- **2026-09-01 — Backend mimarisi: modüler monolit.** Tek Go modülü. İki process:
  `cmd/api` (stateless, yatay ölçeklenir) + `cmd/indexer` (tekil; agregasyon =
  içinde goroutine). Birbirine ağ çağrısı YOK — iletişim Postgres üzerinden
  (+ `LISTEN/NOTIFY`). Aynı kutuda, birlikte deploy. gRPC YOK, mikroservis YOK.
- **2026-09-01 — API = REST/JSON.** Go `huma` (Go tiplerinden bedava OpenAPI +
  validation) → OpenAPI'den frontend'e tipli TS client (tek yönlü codegen).
  Canlı veri = SSE. Sistemdeki tek "RPC" = zincir node'una JSON-RPC (`ethclient`).
- **2026-09-01 — Backend mimarisi (detay, spec girdisi):**
  - Hexagonal + feature-oriented modüller: `launch, trading, token, holder, candle,
    stats, metadata`. Interface tüketen yerde tanımlı; `store/postgres` implement eder.
  - DIP çizgisi: domain'de pgx/sqlc/ethclient **YASAK**; `common.Address/Hash`,
    `*big.Int` value type **SERBEST** (ürün EVM-native).
  - `chain/` yalnız infra (RPC/logs/blocks/decode). Reorg + sync loop + routing = `indexer/`.
    Faz geçişi (curve→graduated) = `launch` service, chain'in işi değil.
  - `candle`/`stats` (aggregate) indexer'dan kavramsal ayrı: canonical trades →
    aggregator → derived. Artımlı güncelleme + periyodik reconcile sweep. v1'de
    `cmd/indexer` goroutine.
  - **UnitOfWork:** 1 blok chunk = 1 DB tx, çok modüllü. `WithinTx(ctx, fn(Repositories))`;
    pgx.Tx domain'e sızmaz (sqlc `DBTX`).
  - **Event sıralaması:** işlemeden önce kesin sırala `(block_number, tx_index, log_index)`.
  - **Unified market trades:** canonical split kalır (`trades` curve / `pool_swaps` DEX);
    candle/volume/ATH/feed/history ortak `market_trades` VIEW'inden. DEX fiyatı için
    graduation'da `token_is_token0` saklanır. Perf gerekirse materialize.
  - **store/ layout:** tek paket `internal/store/postgres`, feature başına dosya +
    `uow.go` + `db.go`.
- **2026-09-01 — Auth: Privy tek model (custom SIWE İPTAL).** Backend Privy JWT'sini
  JWKS cache middleware ile doğrular → verified wallet(lar). Metadata yazımı:
  `tokens.creator ∈ user.wallets`. `/auth/siwe/*` + session tablosu yok.
- **2026-09-01 — SSE reliability = best-effort.** Postgres = source of truth; SSE =
  canlı bildirim. Commit sonrası publish'ten önce process ölürse event kaçabilir =
  veri kaybı DEĞİL. Reconnect eden client önce REST snapshot, sonra SSE delta.
- **2026-09-01 — Onay bekleyen bloğundan onaylananlar:** (2) Limit/Orders v1 dışı,
  (3) constant-product curve, (4) Uniswap v2 pair + LP burn, (5) v1'de sadece ETH
  pair. **(1) parçalama ve (6) forum/ticker erteleme — "biraz daha bakılacak", parked.**
- **2026-09-01 — Indexer bölünmesi:** trades → ana indexer (event stream'e ideal);
  holders listesi → ayrı tablo/indexer ya da graduation sonrası snapshot
  (her transfer'de balance+sıralama subgraph'i şişirir, gecikir).
- **2026-09-01 — Fiyat/MC/FDV/ATH:** kaynak kendi indexer'ımız. Curve öncesi
  fiyat curve'den, sonrası havuz Swap event'lerinden. MC/FDV = fiyat × arz,
  ATH = kendi geçmişimizin max'ı. Dexscreener/GeckoTerminal yalnız dışa link.
- **2026-09-01 — v1/v2 UI toggle YOK.** Tek launch motoruyla başlıyoruz.
  Kontratlar versiyonlanır (yeni deploy + registry), kullanıcıya tek akış.
- **2026-09-01 — Bütçe: SIFIR MALİYET.** Her servis ücretsiz tier'da. Cepten
  para yok. Geliştirme testnet'te (gas faucet'ten bedava). Ücretli/mainnet
  konuları (dış audit, Vercel Pro, kalıcı DB, özel domain, mainnet deploy gas'i,
  RPC hacmi) "sonra bakarız". Protokol ücretleri v1'de config'te, testnet'te
  0/nominal, treasury = kendi cüzdan.
- **2026-09-01 — Chart mimarisi:** Lightweight Charts sadece **çizici**. OHLC/
  fiyat serisini **indexer üretir** (Trade event fiyatları → zaman kovaları →
  open/high/low/close/volume) ve API döner. Image #9 grafiği area chart =
  "zamana göre fiyat" serisi yeter; mum modu için OHLC tablosu.
- **2026-09-01 — Zincir & dev ortamı: EVM-agnostik core contracts, hedef = Robinhood Chain.**
  Stack = Solidity + Foundry. Zincire özel adres/servis/varsayım contract'a
  gömülmez; `zincir → {RPC, DEX router, explorer, chainId, WETH}` config eşlemesi.
  - Local: Anvil (gerekince RH testnet fork)
  - Birincil testnet: **Robinhood Chain Testnet — chainId 46630**,
    RPC `rpc.testnet.chain.robinhood.com`, explorer `explorer.testnet.chain.robinhood.com`,
    Alchemy `robinhood-testnet.g.alchemy.com`
  - Base Sepolia: isteğe bağlı taşınabilirlik kontrolü, zorunlu değil
  - Mainnet: **Robinhood Chain — chainId 4663**, RPC `rpc.mainnet.chain.robinhood.com`,
    explorer `robinhoodchain.blockscout.com`, Alchemy `robinhood-mainnet.g.alchemy.com`
  - RH Chain = EVM-equivalent, Arbitrum Nitro/Orbit, blob DA, gas ETH; standart
    tooling değişiklik gerektirmeden çalışıyor. Testnet Şub 2026, mainnet Tem 2026.
  - **Graduation DEX = Uniswap v2 (RH Chain'de 1. günden canlı: v2/v3/v4/UniswapX)**
    - `UniswapV2Factory` = `0x8bceaa40b9acdfaedf85adf4ff01f5ad6517937f`
    - `UniswapV2Router02` = `0x89e5db8b5aa49aa85ac63f691524311aeb649eba`
    - WETH adresi: RH Chain contracts dokümanından teyit edilecek
  - **Faucet yok** — testnet ETH canonical Arbitrum bridge ile Sepolia'dan köprüleniyor
    (veya Alchemy testnet kredisi). Kurulum adımı.
  - **Rakip/referans:** pons + **Uniswap'in kendi RH Chain launchpad'i** (analiz edilecek).
  - Proje **Solana/Anchor değil** — baştan beri EVM (referans, wallet, DEX hepsi EVM).

### Parked — "biraz daha bakılacak" (2026-09-01)

- **Proje parçalama:** A Core launchpad → B Indexer+Analytics → C Forum → D Docs.
  (Karar verilmedi.)
- **Forum + ticker tape:** alt-proje C'ye erteleme önerisi. (Karar verilmedi.)
  Ticker verisi opsiyonu: Finnhub / Twelve Data ücretsiz tier, 15dk gecikmeli, cache.

## Açık sorular

- **[KRİTİK] Hedef zincir + geliştirme ortamı.** Robinhood Chain mainnet durumu /
  chainId / RPC / explorer / faucet belirsiz; "tokenize hisse" özelliği o zincire
  özel. Kontrat + indexer + RPC + wallet config'inin tamamını bu belirliyor.
  Öneri: EVM-agnostik yaz, dev = lokal Anvil + Base Sepolia, mainnet hedefi sonra.
- Bonding curve tam parametreleri: toplam arz, curve/LP oranı, launch fee,
  trade fee, snipe-tax süresi/oranı, graduation eşiği (referans: 0.0005 fee,
  %1 trade, 99% snipe 3s, 4.2 ETH graduation).
- Graduation LP: burn mü locker mı? Locker ise süre?
- Forum auth + moderasyon detayı (alt-proje C'de netleşecek).

## Spec & plan dokümanları

- `docs/specs/2026-09-01-backend-core-design.md` — Backend Core tasarımı
  (indexer + read API + curve math). Durum: onaylandı (2026-09-01).
- Backend, 3 ardışık plana bölündü (hepsi bu spec'i uygular):
  1. `docs/plans/2026-09-01-backend-foundations.md` — scaffold + config/registry +
     `curve/` math (differential test) + `store/` (şema + migration + sqlc + UoW).
     **12 task, yazıldı, execution bekliyor.**
  2. Indexer (chain infra + sync loop + feature ingestion + aggregation) — yazılacak.
  3. API (apiserver + Privy auth + read endpoint'leri + SSE) — yazılacak.

## Alt-proje A — ekonomi & kontrat parametreleri (ÇALIŞMA HALİNDE)

> Bunlar "tek doğru" değil; ekonomiyi + trust modelini belirleyen parametreler.
> Başlangıç değerleri, curve simülasyonu sonrası ayarlanabilir.
> Durum: önerilen, onay bekliyor (bkz. mesajlaşma 2026-09-01).

### Token
- Toplam arz **1,000,000,000** (sabit, mint yok), **18 decimals**
- Dağılım: **800M** bonding curve (`T_r`) · **200M** graduation likidite (`L`)
  — 80/20 curve simülasyonuyla tutarlı bulundu (aşağı bak), yine de değişebilir

### Bonding curve — virtual-reserve constant-product
State: `x` = ETH rezervi, `y` = token rezervi, sabit `x·y = k`
- Init: `x=x0`, `y=y0`, `k=x0·y0`
- Alım (`dxEff` = trade fee düşülmüş ETH): `dy = y − k/(x+dxEff)`; `x += dxEff`; `y −= dy`
- Satım (`dy` token): `dxOut = x − k/(y+dy)`; `y += dy`; `x −= dxOut`; trade fee `dxOut`'tan alınır
- Spot fiyat `P = x/y`
- Satılan token `= y0 − y`; graduation koşulu: `y ≤ y0 − T_r` (eşdeğer: toplanan gerçek ETH `≥ G`)
- Trade fee curve DIŞINDA skim edilir (k'ya girmez) → `G` temiz curve ETH'i

**Parametre türetimi** (kafadan seçilmez — "boşluksuz graduation" kısıtından:
curve son fiyatı = Uniswap havuzu açılış fiyatı):
```
y0 = T_r² / (T_r − L)
x0 = G · L / (T_r − L)
launch→graduation FDV çarpanı = (T_r / L)²        (G'den bağımsız)
başlangıç FDV = G·L·S / T_r²
graduation FDV = G·S / L
```

**LP split senaryoları** (`G = 4.2 ETH`, `S = 1B`, ETH ~$4000 varsayımı):

| Split (T_r/L) | Çarpan | x0 | y0 | başl. FDV | grad. FDV | Karakter |
|---|---|---|---|---|---|---|
| 700M/300M | 5.4x | 3.15 ETH | 1.225B | ~2.6 ETH (~$10k) | 14 ETH (~$56k) | kalın likidite |
| **800M/200M** | **16x** | 1.4 ETH | 1.0667B | ~1.31 ETH (~$5.2k) | 21 ETH (~$84k) | **öneri** |
| 900M/100M | 81x | 0.525 ETH | 1.0125B | ~0.52 ETH (~$2k) | 42 ETH (~$168k) | ince likidite, degen |

`G` değişimi FDV'leri ölçekler, çarpanı değiştirmez.

**Simülasyon sonucu (80/20, G=4.2, ETH~$4000) — 2026-09-01:**
- Launch: spot 1.3125e-9 ETH/tok, FDV 1.3125 ETH (~$5.25k), dolaşan MC 0
- Graduation: spot 2.1e-8 (16x), FDV 21 ETH (~$84k), dolaşan MC 16.8 ETH (~$67k)
- Havuz açılış fiyatı = curve son fiyatı = 2.1e-8 (arb boşluğu yok) ✓
- Konvekslik: ilk %50 token → %20 ETH; son %25 token → %57 ETH
- Dev buy max %1 (10M tok) launch'ta ≈ 0.0133 ETH (~$54), başlangıç FDV'ye ~sıfır etki
- **KRİTİK:** havuz ETH derinliği = G, split'ten bağımsız. "Daha derin havuz için
  70/30" YANLIŞ — split yalnız çarpanı + fiyat seviyesini belirler. Derinlik kolu = G.
- Taze havuz (4.2 ETH + 200M tok): 0.5 ETH alım → +%25 fiyat; 1 ETH → +%53. İnce ama
  işlenebilir; pump.fun graduation havuzu profili.
- pump.fun kıyası: başl. FDV $4-5k / grad FDV $60-70k / çarpan 10-15x → aynı lig.
- **Karar 3 açık:** G = 4.2 ETH (pump.fun modeli, çok graduation + ince havuz) VS
  6-8 ETH (kalite filtresi, az graduation + derin havuz).

### Fee
- Create: **0.0005 ETH** sabit → protocol
- Her trade (**yalnız curve fazı**): **%1** = %0.5 protocol + %0.5 creator
  - `creatorFees[token][creator]` birikir, creator çeker (`CreatorFeesClaimed`)
- ⚠️ Graduation SONRASI vanilla Uniswap → protocol/creator kesintisi YOK.
  Post-grad fee yakalama = gelecek (Uniswap V4 hook; V2/V4 kararını DEX'e bağlar).
- Snipe tax: **v1'de YOK**
- Developer buy: **izin var, launch anında max %1 supply**
- Creator geliri: curve fazı trade fee payı (yukarıdaki %0.5)

### Graduation
Akış: curve → threshold → curve trading kapanır → toplanan ETH + `L` token → DEX havuzu → LP token → burn
- ⚠️ "LP burn" V2-style likiditeye bağlar; V3/V4'te likidite ERC-20 LP token değil.
  RH Chain'de Uniswap v2 canlı + adresler elde (bkz. zincir kararı) ama tasarımda
  **soft requirement** tut, DEX entegrasyonu doğrulanınca kesinleştir.
- Graduation fee (varsa) havuza giden ETH'i azaltır → küçük arb boşluğu; sonra karar.

### Factory & upgrade
- **EIP-1167 minimal clone**, ortak implementation, token başına ayrı storage (ucuz)
- **Non-upgradeable.** Upgrade gerekince `CurveImplementationV1 / V2`; factory yeni
  launch'ları yeni impl'e yönlendirir, mevcut tokenlar dokunulmaz.

### Admin / trust modeli
- Emergency pause → **multisig**
- Fee/config değişikliği → **multisig + timelock**
- Mevcut token/curve mantığı → admin tarafından **DEĞİŞTİRİLEMEZ**
  (admin "şu curve'ü değiştir / parayı başka yere gönder" yetkisine sahip olamaz)

### Parametre yönetimi ilkesi (2026-09-01)
Tüm launch parametreleri (`x0,y0,T_r,L,G`, fee'ler) launch anında clone'un
**değişmez storage'ına snapshot'lanır**. Factory yalnız GELECEK launch'lar için
değiştirilebilir default tutar. Başlamış launch'ın kuralları hiç değişmez.

### Event şeması (backend'in bağlı olduğu arayüz) — 2026-09-01
```solidity
// Factory
event TokenLaunched(
    address indexed token, address indexed curve, address indexed creator,
    uint256 totalSupply,      // 1e27
    uint256 virtualEth,       // x0 snapshot
    uint256 virtualToken,     // y0 snapshot
    uint256 curveTokens,      // T_r
    uint256 lpTokens,         // L
    uint256 graduationEth,    // G
    uint16  tradeFeeBps,      // 100 = %1
    uint16  protocolShareBps  // 5000 = %50
);
// Curve — her alım/satım (yalnız curve fazı)
event Trade(
    address indexed token, address indexed trader, bool isBuy,
    uint256 ethAmount,        // GROSS (fee öncesi)
    uint256 tokenAmount,
    uint256 protocolFee, uint256 creatorFee,   // ETH
    uint256 newEthReserve, uint256 newTokenReserve  // x, y sonrası
);
// Curve — bir kez
event Graduated(
    address indexed token, uint256 ethToPool, uint256 tokensToPool,
    address lpPair, uint256 graduationFee
);
// Curve
event CreatorFeesClaimed(address indexed token, address indexed creator, uint256 amount);
```
- `ts` yok — log zaten blok/timestamp taşıyor.
- Protocol fee **anında treasury'e** transfer (accrual yok, `protocolFee` Trade'de görünür).
- Creator fee **birikir**, creator çeker (`CreatorFeesClaimed`).

### İndexleme modeli (backend, token başına)
| Faz | Fiyat kaynağı | Holders kaynağı |
|-----|---------------|-----------------|
| Graduation öncesi | bizim `Trade` (P = x/y) | ERC-20 `Transfer` |
| Graduation sonrası | Uniswap v2 pair `Swap` + `Sync` | ERC-20 `Transfer` |
`Graduated` = faz anahtarı: o token için `Trade` dinlemeyi bırak, Uniswap pair'ini dinle.

### Karar durumu
1. **Token ekonomisi** — ✅ 1B / 18dec · 800M curve / 200M LP (80/20 provisional)
2. **Curve ekonomisi** — ✅ virtual-reserve constant-product; x0=1.4, y0=1.0667B, k türetildi;
   simülasyon yapıldı (yukarı bak)
3. **Fee ekonomisi** — ✅ create 0.0005 ETH → protocol; trade %1 = %0.5/%0.5, yalnız curve fazı
4. **G (graduation)** — ✅ 4.2 ETH default, gelecek launch'lar için configurable, launch'ta snapshot
5. **Event şeması** — ✅ KİLİTLİ (yukarıdaki)
6. **Metadata** — ✅ tamamen off-chain (bizim Postgres). Creator SIWE ile kimliklenip
   API'ye yazar/düzenler; API `creator` adresini `TokenLaunched`'dan doğrular.
   description + görsel + X/Telegram. name/symbol zaten ERC-20'de. Event'te URI yok.
   Dezavantaj kabul: metadata taşınabilir/kalıcı değil; sonradan ipfs:// ayna eklenebilir.
7. **graduationFee** — ✅ v1'de 0 (tüm G havuza, arb boşluğu yok)

## Kodlamadan önce belirlenecekler (checklist)

Durum: ✅ karar · 🔴 repo geneli, koddan önce · 🟡 alt-proje A'dan önce · ⚪ v1'de atla

### Repo geneli (🔴)
- [x] **Hedef zincir + dev ortamı** — ✅ EVM-agnostik core; hedef Robinhood Chain (testnet 46630 / mainnet 4663); Uniswap v2 graduation için hazır
- [x] **Kontrat stack** — ✅ Solidity + Foundry
- [ ] Repo yapısı — monorepo (pnpm workspaces + Turborepo): `contracts/ web/ indexer/ docs/`
- [ ] Frontend stack — Next.js (App Router) + TS + Tailwind + shadcn/ui
- [ ] API katmanı — tRPC / REST / GraphQL?
- [ ] DB — Postgres (+ Redis?)
- [ ] Hosting — web: Vercel Hobby · indexer+DB: Railway/Render/Fly/Neon free
- [ ] CI + test politikası — GitHub Actions; lint+typecheck+Foundry test zorunlu; TDD

### Alt-proje A: ekonomi + kontrat tasarımı (🟡)
- [ ] Token: düz ERC-20 sabit arz — toplam arz (1B?), decimals 18
- [ ] Curve parametreleri: başlangıç sanal ETH rezervi, curve/LP token oranı (%80/20?), graduation eşiği (ref 4.2 ETH)
- [ ] Ücretler: launch fee (0.0005), trade fee (%1) — kime, bölünüyor mu (protokol/yaratıcı/referans)
- [ ] Snipe tax: oran (%99), süre (3s), toplanınca nereye
- [ ] Developer buy: izin/max %
- [ ] Yaratıcı geliri: sürekli fee + claim var mı
- [ ] Graduation: DEX router (Uniswap v2 fork adresi), LP → burn mü locker mı
- [ ] Factory deseni: EIP-1167 minimal proxy clone vs tam deploy
- [ ] **Event şeması** — `TokenLaunched Trade Graduated FeesClaimed ...` (B buna bağlı, erken sabitle)
- [ ] Admin/güvenlik: pause/upgrade/fee yetkisi — multisig + timelock?
- [ ] Audit planı: Slither + iç review (v1); dış audit mainnet öncesi
- [ ] Anti-abuse: max wallet %, cooldown — yoksa yok?

### Alt-proje A: minimal indexer A'ya dahil (🟡)
Explore/Graduated'da "hacme/market cap'e göre sırala" var → day 1'den indexer şart.
- [ ] Arama (name/ticker/address) — Postgres full-text
- [ ] Sayfalama — cursor-based
- [ ] Canlı güncelleme — websocket mi polling mi
- [ ] OHLC/fiyat serisi üretimi

### v1'de ATLA (⚪)
i18n, telemetri, referral, Limit/Orders, Stocks pairing, forum, mobil.

### Paralel / metin işi (🟢)
Terms/Privacy/risk metni, geo-restriction politikası (US/OFAC blok?), domain/DNS,
`AGENTS.md` komut+kod-stili bölümleri.

## Kaynaklar / linkler

- Referans ürün: https://pons.family — X: @ponsdotfamily
- Robinhood Chain dev docs: https://docs.robinhood.com/chain/connecting · contracts: https://docs.robinhood.com/chain/contracts
- RH Chain rehberleri: https://www.quicknode.com/guides/robinhood/what-is-robinhood-chain · https://chainstack.com/what-is-robinhood-chain/
- Uniswap on RH Chain: https://blog.uniswap.org/robinhood-chain-is-live · v2 deployments: https://developers.uniswap.org/docs/protocols/v2/deployments
- Uniswap RH Chain launchpad (rakip): https://crypto.news/uniswap-launches-first-robinhood-chain-launchpad/
- Reown AppKit: https://reown.com/appkit  ·  Cloud: https://cloud.reown.com
- RainbowKit: https://rainbowkit.com  ·  wagmi: https://wagmi.sh  ·  viem: https://viem.sh
- Ponder: https://ponder.sh
- The Graph: https://thegraph.com  ·  Envio: https://envio.dev  ·  Subsquid: https://sqd.dev
- Dune: https://dune.com
