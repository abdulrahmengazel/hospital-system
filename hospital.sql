-- ============================================================
-- Hospital Management System Database
-- Improved PostgreSQL Schema
-- ============================================================
-- Glossary (Turkish -> English):
--   ameliyat           surgery
--   asi                vaccination
--   bolum              department
--   doktor             doctor
--   doktorilac         doctor-medication junction
--   evrak              document
--   hasta              patient
--   hastailac          patient-medication junction
--   hastalaboratuvar   patient-laboratory junction
--   hastaziyaretci     patient-visitor
--   hemsire            nurse
--   hemsire_yatanhasta nurse-inpatient junction (replaces hemsire.yatanhasta_id)
--   ilac               medication
--   laboratuvar        laboratory
--   oda                room
--   personel           staff
--   randevu            appointment
--   rapor              report
--   sevk               referral
--   sigorta            insurance
--   tahlilvesonuclar   test and results
--   tedavi             treatment
--   vezneucreti        cashier fee
--   yatanhasta         inpatient
-- ============================================================

BEGIN;

-- ============================================================
-- SECTION 1: ENUM TYPES
-- ============================================================

CREATE TYPE public.randevu_durumu_t AS ENUM (
    'Beklemede', 'Tamamlandı', 'İptal', 'Gelmedi'
);

CREATE TYPE public.evrak_durumu_t AS ENUM (
    'Aktif', 'Arşivlendi', 'İptal'
);

CREATE TYPE public.odeme_durumu_t AS ENUM (
    'Ödendi', 'Beklemede', 'İptal'
);

CREATE TYPE public.bolum_tipi_t AS ENUM (
    'Acil', 'Dahiliye', 'Cerrahi', 'Kardiyoloji', 'Nöroloji',
    'Onkoloji', 'Ortopedi', 'Pediatri', 'Psikiyatri', 'Radyoloji',
    'Yoğun Bakım', 'Üroloji', 'Dermatoloji', 'Göz', 'KBB',
    'Kadın Doğum', 'Romatoloji', 'Göğüs Hastalıkları',
    'Fizik Tedavi', 'Tanı', 'Hematoloji', 'Diğer'
);

CREATE TYPE public.cinsiyet_t AS ENUM ('E', 'K');

CREATE TYPE public.kan_grubu_t AS ENUM (
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
);

-- ============================================================
-- SECTION 2: AUDIT TRIGGER FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.guncelleme_tarihi_guncelle()
RETURNS TRIGGER AS $$
BEGIN
    NEW.guncelleme_tarihi = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SECTION 3: TABLE DEFINITIONS
-- (ordered to respect FK dependencies)
-- ============================================================

-- sigorta (insurance) — no dependencies
CREATE TABLE IF NOT EXISTS public.sigorta
(
    sigorta_id              serial          NOT NULL,
    sigortasirketi          varchar(50)     NOT NULL,
    policenumarasi          varchar(50)     NOT NULL,
    sigortaturu             varchar(50)     NOT NULL,
    sigortabaslangictarihi  date            NOT NULL,
    sigortabitistarihi      date            NOT NULL,
    sigortaucreti           numeric(10, 2),
    olusturulma_tarihi      timestamptz     NOT NULL DEFAULT NOW(),
    guncelleme_tarihi       timestamptz     NOT NULL DEFAULT NOW(),
    CONSTRAINT sigorta_pkey               PRIMARY KEY (sigorta_id),
    CONSTRAINT sigorta_policenumarasi_key UNIQUE (policenumarasi),
    CONSTRAINT sigorta_tarihleri_chk      CHECK (sigortabitistarihi > sigortabaslangictarihi)
);

-- personel (staff) — no dependencies
CREATE TABLE IF NOT EXISTS public.personel
(
    personel_id         serial       NOT NULL,
    ad                  varchar(50)  NOT NULL,
    soyad               varchar(50)  NOT NULL,
    gorev               varchar(50)  NOT NULL,
    personeltipi        varchar(50)  NOT NULL,
    personelunvan       varchar(50)  NOT NULL,
    telefon             varchar(15),
    email               varchar(100),
    dogumtarihi         date,
    issegiristarih      date,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT personel_pkey      PRIMARY KEY (personel_id),
    CONSTRAINT personel_email_key UNIQUE (email)
);

-- bolum (department) — depends on personel (bolumsorumlusu_id)
CREATE TABLE IF NOT EXISTS public.bolum
(
    bolum_id            serial        NOT NULL,
    bolumadi            varchar(50)   NOT NULL,
    bolumtipi           bolum_tipi_t  NOT NULL,
    bolumsorumlusu_id   integer,
    olusturulma_tarihi  timestamptz   NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz   NOT NULL DEFAULT NOW(),
    CONSTRAINT bolum_pkey PRIMARY KEY (bolum_id)
);

-- laboratuvar (laboratory) — no dependencies
CREATE TABLE IF NOT EXISTS public.laboratuvar
(
    laboratuvar_id      serial       NOT NULL,
    laboratuvaradi      varchar(50)  NOT NULL,
    laboratuvartipi     varchar(50),
    laboratuvartelefon  varchar(15),
    laboratuvaremail    varchar(100) NOT NULL,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT laboratuvar_pkey PRIMARY KEY (laboratuvar_id)
);

-- oda (room) — no dependencies; dolu boolean removed (use oda_doluluk view)
CREATE TABLE IF NOT EXISTS public.oda
(
    oda_id              serial       NOT NULL,
    odanumarasi         integer      NOT NULL,
    odaturu             varchar(100) NOT NULL,
    kapasite            integer      NOT NULL,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT oda_pkey         PRIMARY KEY (oda_id),
    CONSTRAINT oda_kapasite_chk CHECK (kapasite > 0)
);

-- doktor (doctor) — depends on bolum; added telefon, email, tcno
CREATE TABLE IF NOT EXISTS public.doktor
(
    doktor_id           serial       NOT NULL,
    ad                  varchar(50)  NOT NULL,
    soyad               varchar(50)  NOT NULL,
    uzmanlik            varchar(50)  NOT NULL,
    bolum_id            integer,
    telefon             varchar(15),
    email               varchar(100),
    tcno                varchar(11),
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT doktor_pkey      PRIMARY KEY (doktor_id),
    CONSTRAINT doktor_email_key UNIQUE (email),
    CONSTRAINT doktor_tcno_key  UNIQUE (tcno)
);

-- hasta (patient) — depends on sigorta; added cinsiyet, kan_grubu, adres, tcno
CREATE TABLE IF NOT EXISTS public.hasta
(
    hasta_id            serial       NOT NULL,
    sigorta_id          integer,
    ad                  varchar(50)  NOT NULL,
    soyad               varchar(50)  NOT NULL,
    uyruk               varchar(50),
    dogumtarihi         date         NOT NULL,
    telefon             varchar(15),
    cinsiyet            cinsiyet_t,
    kan_grubu           kan_grubu_t,
    adres               text,
    tcno                varchar(11),
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT hasta_pkey     PRIMARY KEY (hasta_id),
    CONSTRAINT hasta_tcno_key UNIQUE (tcno)
);

-- ilac (medication) — no dependencies; doktor_id/hasta_id removed (use junction tables)
CREATE TABLE IF NOT EXISTS public.ilac
(
    ilac_id             serial       NOT NULL,
    ilacadi             varchar(50)  NOT NULL,
    doz                 varchar(50),
    ilactipi            varchar(50)  NOT NULL,
    ilacfiyat           numeric(10, 2),
    uretimtarihi        date         NOT NULL,
    sonkullanmatarihi   date         NOT NULL,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT ilac_pkey        PRIMARY KEY (ilac_id),
    CONSTRAINT ilac_tarihler_chk CHECK (sonkullanmatarihi > uretimtarihi)
);

-- yatanhasta (inpatient) — depends on hasta, oda
CREATE TABLE IF NOT EXISTS public.yatanhasta
(
    yatanhasta_id       serial      NOT NULL,
    hasta_id            integer,
    oda_id              integer,
    yatistarihi         date        NOT NULL,
    taburcutarihi       date,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT yatanhasta_pkey         PRIMARY KEY (yatanhasta_id),
    CONSTRAINT yatanhasta_tarihler_chk CHECK (taburcutarihi IS NULL OR taburcutarihi >= yatistarihi)
);

-- hemsire (nurse) — yatanhasta_id removed; hemsire_yatanhasta junction used instead
CREATE TABLE IF NOT EXISTS public.hemsire
(
    hemsire_id          serial       NOT NULL,
    ad                  varchar(50)  NOT NULL,
    soyad               varchar(50)  NOT NULL,
    tcno                varchar(11)  NOT NULL,
    telefonno           varchar(15)  NOT NULL,
    email               varchar(100) NOT NULL,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT hemsire_pkey      PRIMARY KEY (hemsire_id),
    CONSTRAINT hemsire_email_key UNIQUE (email),
    CONSTRAINT hemsire_tcno_key  UNIQUE (tcno)
);

-- hemsire_yatanhasta (nurse-inpatient junction) — depends on hemsire, yatanhasta
CREATE TABLE IF NOT EXISTS public.hemsire_yatanhasta
(
    id                  serial      NOT NULL,
    hemsire_id          integer     NOT NULL,
    yatanhasta_id       integer     NOT NULL,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT hemsire_yatanhasta_pkey PRIMARY KEY (id),
    CONSTRAINT hemsire_yatanhasta_uniq UNIQUE (hemsire_id, yatanhasta_id)
);

-- randevu (appointment) — depends on hasta, doktor; added notlar, iptal_nedeni
CREATE TABLE IF NOT EXISTS public.randevu
(
    randevu_id          serial           NOT NULL,
    hasta_id            integer          NOT NULL,
    doktor_id           integer,
    randevutarihi       date             NOT NULL,
    randevusaati        time             NOT NULL,
    randevudurumu       randevu_durumu_t NOT NULL,
    notlar              text,
    iptal_nedeni        text,
    olusturulma_tarihi  timestamptz      NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz      NOT NULL DEFAULT NOW(),
    CONSTRAINT randevu_pkey PRIMARY KEY (randevu_id)
);

-- rapor (report) — depends on doktor, hasta; added sonuc
CREATE TABLE IF NOT EXISTS public.rapor
(
    rapor_id            serial       NOT NULL,
    doktor_id           integer,
    hasta_id            integer,
    raporturu           varchar(100) NOT NULL,
    tarih               date         NOT NULL,
    icerik              text,
    sonuc               text,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT rapor_pkey PRIMARY KEY (rapor_id)
);

-- ameliyat (surgery) — depends on hasta, doktor, hemsire; added sure, sonuc
CREATE TABLE IF NOT EXISTS public.ameliyat
(
    ameliyat_id         serial      NOT NULL,
    hasta_id            integer,
    doktor_id           integer,
    hemsire_id          integer,
    ameliyatturu        varchar(50),
    ameliyattarihi      date        NOT NULL,
    ameliyatsaati       time,
    sure                integer,
    sonuc               text,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT ameliyat_pkey     PRIMARY KEY (ameliyat_id),
    CONSTRAINT ameliyat_sure_chk CHECK (sure IS NULL OR sure > 0)
);

-- asi (vaccination) — depends on hasta, hemsire
CREATE TABLE IF NOT EXISTS public.asi
(
    asi_id              serial      NOT NULL,
    hasta_id            integer     NOT NULL,
    asituru             varchar(50) NOT NULL,
    uygulamatarihi      date        NOT NULL,
    hemsire_id          integer,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT asi_pkey PRIMARY KEY (asi_id)
);

-- tedavi (treatment) — depends on hasta, doktor; circular FK with vezneucreti added via ALTER
CREATE TABLE IF NOT EXISTS public.tedavi
(
    tedavi_id           serial       NOT NULL,
    hasta_id            integer,
    doktor_id           integer,
    tedavituru          varchar(100) NOT NULL,
    baslangictarihi     date         NOT NULL,
    bitistarihi         date,
    aciklama            text,
    maliyet             numeric(10, 2),
    vezneucret_id       integer,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT tedavi_pkey         PRIMARY KEY (tedavi_id),
    CONSTRAINT tedavi_tarihler_chk CHECK (bitistarihi IS NULL OR bitistarihi >= baslangictarihi)
);

-- vezneucreti (cashier fee) — depends on hasta, tedavi (circular with tedavi)
CREATE TABLE IF NOT EXISTS public.vezneucreti
(
    vezneucreti_id      serial         NOT NULL,
    hasta_id            integer,
    tedavi_id           integer,
    ucretturu           varchar(100)   NOT NULL,
    ucrettarihi         date           NOT NULL,
    ucretmiktari        numeric(10, 2),
    odemedurumu         odeme_durumu_t NOT NULL,
    odemetarihi         date,
    olusturulma_tarihi  timestamptz    NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz    NOT NULL DEFAULT NOW(),
    CONSTRAINT vezneucreti_pkey PRIMARY KEY (vezneucreti_id)
);

-- evrak (document) — depends on hasta, personel, tedavi
CREATE TABLE IF NOT EXISTS public.evrak
(
    evrak_id            serial         NOT NULL,
    hasta_id            integer,
    personel_id         integer,
    tedavi_id           integer,
    evrakturu           varchar(50)    NOT NULL,
    evraktarihi         date           NOT NULL,
    evrakaciklamasi     text,
    evrakdurumu         evrak_durumu_t NOT NULL,
    olusturulma_tarihi  timestamptz    NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz    NOT NULL DEFAULT NOW(),
    CONSTRAINT evrak_pkey PRIMARY KEY (evrak_id)
);

-- sevk (referral) — depends on hasta, doktor
CREATE TABLE IF NOT EXISTS public.sevk
(
    sevk_id             serial      NOT NULL,
    hasta_id            integer     NOT NULL,
    doktor_id           integer,
    sevkturu            varchar(50) NOT NULL,
    sevknedeni          varchar(50) NOT NULL,
    sevktarihi          date        NOT NULL,
    sevksaati           time        NOT NULL,
    sevkedilenyer       varchar(50) NOT NULL,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT sevk_pkey PRIMARY KEY (sevk_id)
);

-- tahlilvesonuclar (test and results) — depends on hasta, laboratuvar, doktor
CREATE TABLE IF NOT EXISTS public.tahlilvesonuclar
(
    tahlilvesonuclar_id serial      NOT NULL,
    hasta_id            integer     NOT NULL,
    laboratuvar_id      integer,
    doktor_id           integer,
    tahlilturu          varchar(50),
    sonuc               varchar(50) NOT NULL,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT tahlilvesonuclar_pkey PRIMARY KEY (tahlilvesonuclar_id)
);

-- doktorilac (doctor-medication junction) — depends on doktor, ilac
CREATE TABLE IF NOT EXISTS public.doktorilac
(
    doktorilac_id       serial      NOT NULL,
    doktor_id           integer     NOT NULL,
    ilac_id             integer     NOT NULL,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT doktorilac_pkey PRIMARY KEY (doktorilac_id),
    CONSTRAINT doktorilac_uniq UNIQUE (doktor_id, ilac_id)
);

-- hastailac (patient-medication junction) — depends on hasta, ilac
CREATE TABLE IF NOT EXISTS public.hastailac
(
    hastailac_id        serial      NOT NULL,
    hasta_id            integer     NOT NULL,
    ilac_id             integer     NOT NULL,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT hastailac_pkey PRIMARY KEY (hastailac_id),
    CONSTRAINT hastailac_uniq UNIQUE (hasta_id, ilac_id)
);

-- hastalaboratuvar (patient-laboratory junction) — depends on hasta, laboratuvar
CREATE TABLE IF NOT EXISTS public.hastalaboratuvar
(
    hastalaboratuvar_id serial      NOT NULL,
    hasta_id            integer     NOT NULL,
    laboratuvar_id      integer     NOT NULL,
    olusturulma_tarihi  timestamptz NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT hastalaboratuvar_pkey PRIMARY KEY (hastalaboratuvar_id),
    CONSTRAINT hastalaboratuvar_uniq UNIQUE (hasta_id, laboratuvar_id)
);

-- hastaziyaretci (patient-visitor) — depends on hasta
CREATE TABLE IF NOT EXISTS public.hastaziyaretci
(
    ziyaretci_id        serial       NOT NULL,
    hasta_id            integer,
    ad                  varchar(100) NOT NULL,
    soyad               varchar(100) NOT NULL,
    ziyarettarihi       date         NOT NULL,
    olusturulma_tarihi  timestamptz  NOT NULL DEFAULT NOW(),
    guncelleme_tarihi   timestamptz  NOT NULL DEFAULT NOW(),
    CONSTRAINT hastaziyaretci_pkey PRIMARY KEY (ziyaretci_id)
);

-- ============================================================
-- SECTION 4: FOREIGN KEY CONSTRAINTS
-- ============================================================

-- bolum
ALTER TABLE public.bolum
    ADD CONSTRAINT bolum_bolumsorumlusu_id_fkey
    FOREIGN KEY (bolumsorumlusu_id) REFERENCES public.personel (personel_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- doktor
ALTER TABLE public.doktor
    ADD CONSTRAINT doktor_bolum_id_fkey
    FOREIGN KEY (bolum_id) REFERENCES public.bolum (bolum_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- hasta
ALTER TABLE public.hasta
    ADD CONSTRAINT hasta_sigorta_id_fkey
    FOREIGN KEY (sigorta_id) REFERENCES public.sigorta (sigorta_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- yatanhasta
ALTER TABLE public.yatanhasta
    ADD CONSTRAINT yatanhasta_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.yatanhasta
    ADD CONSTRAINT yatanhasta_oda_id_fkey
    FOREIGN KEY (oda_id) REFERENCES public.oda (oda_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- hemsire_yatanhasta
ALTER TABLE public.hemsire_yatanhasta
    ADD CONSTRAINT hemsire_yatanhasta_hemsire_id_fkey
    FOREIGN KEY (hemsire_id) REFERENCES public.hemsire (hemsire_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.hemsire_yatanhasta
    ADD CONSTRAINT hemsire_yatanhasta_yatanhasta_id_fkey
    FOREIGN KEY (yatanhasta_id) REFERENCES public.yatanhasta (yatanhasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

-- ameliyat
ALTER TABLE public.ameliyat
    ADD CONSTRAINT ameliyat_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.ameliyat
    ADD CONSTRAINT ameliyat_doktor_id_fkey
    FOREIGN KEY (doktor_id) REFERENCES public.doktor (doktor_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

ALTER TABLE public.ameliyat
    ADD CONSTRAINT ameliyat_hemsire_id_fkey
    FOREIGN KEY (hemsire_id) REFERENCES public.hemsire (hemsire_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- asi
ALTER TABLE public.asi
    ADD CONSTRAINT asi_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.asi
    ADD CONSTRAINT asi_hemsire_id_fkey
    FOREIGN KEY (hemsire_id) REFERENCES public.hemsire (hemsire_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- tedavi
ALTER TABLE public.tedavi
    ADD CONSTRAINT tedavi_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.tedavi
    ADD CONSTRAINT tedavi_doktor_id_fkey
    FOREIGN KEY (doktor_id) REFERENCES public.doktor (doktor_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- circular FK: tedavi -> vezneucreti (added after vezneucreti is created)
ALTER TABLE public.tedavi
    ADD CONSTRAINT tedavi_vezneucret_id_fkey
    FOREIGN KEY (vezneucret_id) REFERENCES public.vezneucreti (vezneucreti_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- vezneucreti
ALTER TABLE public.vezneucreti
    ADD CONSTRAINT vezneucreti_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.vezneucreti
    ADD CONSTRAINT vezneucreti_tedavi_id_fkey
    FOREIGN KEY (tedavi_id) REFERENCES public.tedavi (tedavi_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- evrak
ALTER TABLE public.evrak
    ADD CONSTRAINT evrak_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.evrak
    ADD CONSTRAINT evrak_personel_id_fkey
    FOREIGN KEY (personel_id) REFERENCES public.personel (personel_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

ALTER TABLE public.evrak
    ADD CONSTRAINT evrak_tedavi_id_fkey
    FOREIGN KEY (tedavi_id) REFERENCES public.tedavi (tedavi_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- randevu
ALTER TABLE public.randevu
    ADD CONSTRAINT randevu_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.randevu
    ADD CONSTRAINT randevu_doktor_id_fkey
    FOREIGN KEY (doktor_id) REFERENCES public.doktor (doktor_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- rapor
ALTER TABLE public.rapor
    ADD CONSTRAINT rapor_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.rapor
    ADD CONSTRAINT rapor_doktor_id_fkey
    FOREIGN KEY (doktor_id) REFERENCES public.doktor (doktor_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- sevk
ALTER TABLE public.sevk
    ADD CONSTRAINT sevk_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.sevk
    ADD CONSTRAINT sevk_doktor_id_fkey
    FOREIGN KEY (doktor_id) REFERENCES public.doktor (doktor_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- tahlilvesonuclar
ALTER TABLE public.tahlilvesonuclar
    ADD CONSTRAINT tahlilvesonuclar_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.tahlilvesonuclar
    ADD CONSTRAINT tahlilvesonuclar_laboratuvar_id_fkey
    FOREIGN KEY (laboratuvar_id) REFERENCES public.laboratuvar (laboratuvar_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

ALTER TABLE public.tahlilvesonuclar
    ADD CONSTRAINT tahlilvesonuclar_doktor_id_fkey
    FOREIGN KEY (doktor_id) REFERENCES public.doktor (doktor_id)
    ON UPDATE NO ACTION ON DELETE SET NULL;

-- doktorilac
ALTER TABLE public.doktorilac
    ADD CONSTRAINT doktorilac_doktor_id_fkey
    FOREIGN KEY (doktor_id) REFERENCES public.doktor (doktor_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.doktorilac
    ADD CONSTRAINT doktorilac_ilac_id_fkey
    FOREIGN KEY (ilac_id) REFERENCES public.ilac (ilac_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

-- hastailac
ALTER TABLE public.hastailac
    ADD CONSTRAINT hastailac_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.hastailac
    ADD CONSTRAINT hastailac_ilac_id_fkey
    FOREIGN KEY (ilac_id) REFERENCES public.ilac (ilac_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

-- hastalaboratuvar
ALTER TABLE public.hastalaboratuvar
    ADD CONSTRAINT hastalaboratuvar_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE public.hastalaboratuvar
    ADD CONSTRAINT hastalaboratuvar_laboratuvar_id_fkey
    FOREIGN KEY (laboratuvar_id) REFERENCES public.laboratuvar (laboratuvar_id)
    -- RESTRICT: prevents deleting a laboratory that has patient associations,
    -- preserving the referential integrity of historical test records.
    ON UPDATE NO ACTION ON DELETE RESTRICT;

-- hastaziyaretci
ALTER TABLE public.hastaziyaretci
    ADD CONSTRAINT hastaziyaretci_hasta_id_fkey
    FOREIGN KEY (hasta_id) REFERENCES public.hasta (hasta_id)
    ON UPDATE NO ACTION ON DELETE CASCADE;

-- ============================================================
-- SECTION 5: INDEXES ON FOREIGN KEY COLUMNS
-- ============================================================

CREATE INDEX idx_bolum_bolumsorumlusu      ON public.bolum (bolumsorumlusu_id);
CREATE INDEX idx_doktor_bolum              ON public.doktor (bolum_id);
CREATE INDEX idx_hasta_sigorta             ON public.hasta (sigorta_id);
CREATE INDEX idx_yatanhasta_hasta          ON public.yatanhasta (hasta_id);
CREATE INDEX idx_yatanhasta_oda            ON public.yatanhasta (oda_id);
CREATE INDEX idx_hemsire_yatanhasta_hem    ON public.hemsire_yatanhasta (hemsire_id);
CREATE INDEX idx_hemsire_yatanhasta_yat    ON public.hemsire_yatanhasta (yatanhasta_id);
CREATE INDEX idx_ameliyat_hasta            ON public.ameliyat (hasta_id);
CREATE INDEX idx_ameliyat_doktor           ON public.ameliyat (doktor_id);
CREATE INDEX idx_ameliyat_hemsire          ON public.ameliyat (hemsire_id);
CREATE INDEX idx_asi_hasta                 ON public.asi (hasta_id);
CREATE INDEX idx_asi_hemsire               ON public.asi (hemsire_id);
CREATE INDEX idx_tedavi_hasta              ON public.tedavi (hasta_id);
CREATE INDEX idx_tedavi_doktor             ON public.tedavi (doktor_id);
CREATE INDEX idx_tedavi_vezneucret         ON public.tedavi (vezneucret_id);
CREATE INDEX idx_vezneucreti_hasta         ON public.vezneucreti (hasta_id);
CREATE INDEX idx_vezneucreti_tedavi        ON public.vezneucreti (tedavi_id);
CREATE INDEX idx_evrak_hasta               ON public.evrak (hasta_id);
CREATE INDEX idx_evrak_personel            ON public.evrak (personel_id);
CREATE INDEX idx_evrak_tedavi              ON public.evrak (tedavi_id);
CREATE INDEX idx_randevu_hasta             ON public.randevu (hasta_id);
CREATE INDEX idx_randevu_doktor            ON public.randevu (doktor_id);
CREATE INDEX idx_rapor_hasta               ON public.rapor (hasta_id);
CREATE INDEX idx_rapor_doktor              ON public.rapor (doktor_id);
CREATE INDEX idx_sevk_hasta                ON public.sevk (hasta_id);
CREATE INDEX idx_sevk_doktor               ON public.sevk (doktor_id);
CREATE INDEX idx_tahlil_hasta              ON public.tahlilvesonuclar (hasta_id);
CREATE INDEX idx_tahlil_laboratuvar        ON public.tahlilvesonuclar (laboratuvar_id);
CREATE INDEX idx_tahlil_doktor             ON public.tahlilvesonuclar (doktor_id);
CREATE INDEX idx_doktorilac_doktor         ON public.doktorilac (doktor_id);
CREATE INDEX idx_doktorilac_ilac           ON public.doktorilac (ilac_id);
CREATE INDEX idx_hastailac_hasta           ON public.hastailac (hasta_id);
CREATE INDEX idx_hastailac_ilac            ON public.hastailac (ilac_id);
CREATE INDEX idx_hastalaboratuvar_hasta    ON public.hastalaboratuvar (hasta_id);
CREATE INDEX idx_hastalaboratuvar_lab      ON public.hastalaboratuvar (laboratuvar_id);
CREATE INDEX idx_hastaziyaretci_hasta      ON public.hastaziyaretci (hasta_id);

-- ============================================================
-- SECTION 6: AUDIT UPDATE TRIGGERS
-- ============================================================

CREATE TRIGGER tr_sigorta_guncelleme
    BEFORE UPDATE ON public.sigorta
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_personel_guncelleme
    BEFORE UPDATE ON public.personel
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_bolum_guncelleme
    BEFORE UPDATE ON public.bolum
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_laboratuvar_guncelleme
    BEFORE UPDATE ON public.laboratuvar
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_oda_guncelleme
    BEFORE UPDATE ON public.oda
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_doktor_guncelleme
    BEFORE UPDATE ON public.doktor
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_hasta_guncelleme
    BEFORE UPDATE ON public.hasta
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_ilac_guncelleme
    BEFORE UPDATE ON public.ilac
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_yatanhasta_guncelleme
    BEFORE UPDATE ON public.yatanhasta
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_hemsire_guncelleme
    BEFORE UPDATE ON public.hemsire
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_hemsire_yatanhasta_guncelleme
    BEFORE UPDATE ON public.hemsire_yatanhasta
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_randevu_guncelleme
    BEFORE UPDATE ON public.randevu
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_rapor_guncelleme
    BEFORE UPDATE ON public.rapor
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_ameliyat_guncelleme
    BEFORE UPDATE ON public.ameliyat
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_asi_guncelleme
    BEFORE UPDATE ON public.asi
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_tedavi_guncelleme
    BEFORE UPDATE ON public.tedavi
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_vezneucreti_guncelleme
    BEFORE UPDATE ON public.vezneucreti
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_evrak_guncelleme
    BEFORE UPDATE ON public.evrak
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_sevk_guncelleme
    BEFORE UPDATE ON public.sevk
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_tahlilvesonuclar_guncelleme
    BEFORE UPDATE ON public.tahlilvesonuclar
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_doktorilac_guncelleme
    BEFORE UPDATE ON public.doktorilac
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_hastailac_guncelleme
    BEFORE UPDATE ON public.hastailac
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_hastalaboratuvar_guncelleme
    BEFORE UPDATE ON public.hastalaboratuvar
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

CREATE TRIGGER tr_hastaziyaretci_guncelleme
    BEFORE UPDATE ON public.hastaziyaretci
    FOR EACH ROW EXECUTE FUNCTION public.guncelleme_tarihi_guncelle();

-- ============================================================
-- SECTION 7: VIEWS
-- ============================================================

-- Room occupancy (replaces the removed oda.dolu boolean)
CREATE OR REPLACE VIEW public.oda_doluluk AS
SELECT
    o.oda_id,
    o.odanumarasi,
    o.odaturu,
    o.kapasite,
    COUNT(yh.yatanhasta_id)                                          AS mevcut_hasta,
    o.kapasite - COUNT(yh.yatanhasta_id)                             AS bos_yatak,
    COUNT(yh.yatanhasta_id) >= o.kapasite                            AS dolu
FROM public.oda o
LEFT JOIN public.yatanhasta yh
    ON o.oda_id = yh.oda_id AND yh.taburcutarihi IS NULL
GROUP BY o.oda_id, o.odanumarasi, o.odaturu, o.kapasite;

-- Upcoming (pending) appointments with patient and doctor details
CREATE OR REPLACE VIEW public.aktif_randevular AS
SELECT
    r.randevu_id,
    h.hasta_id,
    h.ad || ' ' || h.soyad           AS hasta_adi,
    d.doktor_id,
    d.ad || ' ' || d.soyad           AS doktor_adi,
    d.uzmanlik,
    r.randevutarihi,
    r.randevusaati,
    r.randevudurumu,
    r.notlar
FROM public.randevu r
JOIN public.hasta  h ON r.hasta_id  = h.hasta_id
LEFT JOIN public.doktor d ON r.doktor_id = d.doktor_id
WHERE r.randevudurumu = 'Beklemede'
  AND r.randevutarihi >= CURRENT_DATE;

-- Current inpatients with room and assigned nurses
CREATE OR REPLACE VIEW public.yatan_hastalar AS
SELECT
    yh.yatanhasta_id,
    h.hasta_id,
    h.ad || ' ' || h.soyad           AS hasta_adi,
    o.odanumarasi,
    o.odaturu,
    yh.yatistarihi,
    STRING_AGG(hem.ad || ' ' || hem.soyad, ', ' ORDER BY hem.soyad) AS hemsireler
FROM public.yatanhasta yh
JOIN  public.hasta   h   ON yh.hasta_id      = h.hasta_id
JOIN  public.oda     o   ON yh.oda_id        = o.oda_id
LEFT JOIN public.hemsire_yatanhasta hym ON yh.yatanhasta_id = hym.yatanhasta_id
LEFT JOIN public.hemsire            hem ON hym.hemsire_id   = hem.hemsire_id
WHERE yh.taburcutarihi IS NULL
GROUP BY yh.yatanhasta_id, h.hasta_id, h.ad, h.soyad,
         o.odanumarasi, o.odaturu, yh.yatistarihi;

-- Unpaid billing records
CREATE OR REPLACE VIEW public.odenmemis_ucretler AS
SELECT
    v.vezneucreti_id,
    h.hasta_id,
    h.ad || ' ' || h.soyad  AS hasta_adi,
    v.ucretturu,
    v.ucretmiktari,
    v.ucrettarihi,
    v.odemedurumu
FROM public.vezneucreti v
JOIN public.hasta h ON v.hasta_id = h.hasta_id
WHERE v.odemedurumu = 'Beklemede';

-- Surgery count per doctor
CREATE OR REPLACE VIEW public.doktor_ameliyat_sayisi AS
SELECT
    d.doktor_id,
    d.ad || ' ' || d.soyad  AS doktor_adi,
    d.uzmanlik,
    COUNT(a.ameliyat_id)     AS ameliyat_sayisi
FROM public.doktor  d
LEFT JOIN public.ameliyat a ON d.doktor_id = a.doktor_id
GROUP BY d.doktor_id, d.ad, d.soyad, d.uzmanlik;

-- ============================================================
-- SECTION 8: SAMPLE DATA
-- ============================================================

-- sigorta
INSERT INTO public.sigorta
    (sigortasirketi, policenumarasi, sigortaturu, sigortabaslangictarihi, sigortabitistarihi, sigortaucreti)
VALUES
    ('Anadolu Sigorta',  'AGS-2021-001', 'Sağlık',          '2021-01-01', '2026-01-01', 2500.00),
    ('Allianz',          'ALZ-2022-100', 'Hayat + Sağlık',   '2022-03-15', '2027-03-15', 3200.00),
    ('Güneş Sigorta',    'GNS-2020-050', 'Tamamlayıcı',      '2020-06-01', '2025-06-01', 1800.00);

-- personel
INSERT INTO public.personel
    (ad, soyad, gorev, personeltipi, personelunvan, telefon, email, dogumtarihi, issegiristarih)
VALUES
    ('Ahmet',   'Yılmaz', 'Yönetici',        'Yönetim',       'Müdür',     '05550001001', 'ahmet.yilmaz@hastane.com',  '1975-04-12', '2010-09-01'),
    ('Fatma',   'Kaya',   'İdari Personel',  'Yönetim',       'Şef',       '05550001002', 'fatma.kaya@hastane.com',    '1982-07-25', '2012-03-15'),
    ('Mehmet',  'Demir',  'Mali İşler',      'Vezne',         'Veznedar',  '05550001003', 'mehmet.demir@hastane.com',  '1980-11-03', '2008-06-01'),
    ('Ayşe',    'Çelik',  'Sekreterlik',     'İdari',         'Sekreter',  '05550001004', 'ayse.celik@hastane.com',    '1990-02-18', '2015-01-10'),
    ('Hüseyin', 'Arslan', 'Bakım-Onarım',    'Teknik',        'Teknisyen', '05550001005', 'huseyin.arslan@hastane.com','1978-09-30', '2011-07-20');

-- bolum (bolumsorumlusu_id references personel)
INSERT INTO public.bolum (bolumadi, bolumtipi, bolumsorumlusu_id)
VALUES
    ('Kardiyoloji Bölümü', 'Kardiyoloji', 1),
    ('Ortopedi Bölümü',    'Ortopedi',    2),
    ('Nöroloji Bölümü',    'Nöroloji',    1),
    ('Acil Servis',        'Acil',        2),
    ('Radyoloji Bölümü',   'Radyoloji',   3);

-- laboratuvar
INSERT INTO public.laboratuvar (laboratuvaradi, laboratuvartipi, laboratuvartelefon, laboratuvaremail)
VALUES
    ('Merkez Laboratuvar',    'Biyokimya',     '05552002001', 'merkez.lab@hastane.com'),
    ('Mikrobiyoloji Labı',    'Mikrobiyoloji', '05552002002', 'mikrobiyoloji.lab@hastane.com');

-- oda (no dolu column)
INSERT INTO public.oda (odanumarasi, odaturu, kapasite)
VALUES
    (101, 'Standart',    2),
    (102, 'Standart',    2),
    (201, 'VIP',         1),
    (202, 'VIP',         1),
    (301, 'Yoğun Bakım', 3);

-- doktor
INSERT INTO public.doktor (ad, soyad, uzmanlik, bolum_id, telefon, email, tcno)
VALUES
    ('Ali',     'Şahin',   'Kardiyoloji', 1, '05553001001', 'ali.sahin@hastane.com',    '12345678901'),
    ('Zeynep',  'Öztürk',  'Ortopedi',    2, '05553001002', 'zeynep.ozturk@hastane.com','23456789012'),
    ('Mustafa', 'Yıldız',  'Nöroloji',    3, '05553001003', 'mustafa.yildiz@hastane.com','34567890123'),
    ('Selin',   'Kara',    'Acil Tıp',    4, '05553001004', 'selin.kara@hastane.com',   '45678901234'),
    ('Emre',    'Doğan',   'Radyoloji',   5, '05553001005', 'emre.dogan@hastane.com',   '56789012345');

-- hasta
INSERT INTO public.hasta
    (sigorta_id, ad, soyad, uyruk, dogumtarihi, telefon, cinsiyet, kan_grubu, adres, tcno)
VALUES
    (1, 'Kadir',   'Yılmaz', 'TC', '1980-05-15', '05554001001', 'E', 'A+',  'Kızılay Mah. No:5, Ankara',  '11111111111'),
    (2, 'Hülya',   'Kaya',   'TC', '1990-08-20', '05554001002', 'K', 'B+',  'Bağcılar Mah. No:12, İstanbul','22222222222'),
    (NULL,'Serkan','Demir',  'TC', '1975-12-01', '05554001003', 'E', 'O+',  'Konak Mah. No:7, İzmir',     '33333333333'),
    (3, 'Rana',    'Çelik',  'TC', '1985-03-25', '05554001004', 'K', 'AB-', 'Nilüfer Mah. No:3, Bursa',   '44444444444'),
    (1, 'Tuncay',  'Arslan', 'TC', '1968-07-10', '05554001005', 'E', 'A-',  'Çankaya Mah. No:9, Ankara',  '55555555555');

-- hemsire
INSERT INTO public.hemsire (ad, soyad, tcno, telefonno, email)
VALUES
    ('Büşra', 'Yılmaz', '66666666666', '05554004001', 'busra.yilmaz@hastane.com'),
    ('Cemre', 'Kara',   '77777777777', '05554004002', 'cemre.kara@hastane.com'),
    ('Deniz', 'Şahin',  '88888888888', '05554004003', 'deniz.sahin@hastane.com');

-- yatanhasta
INSERT INTO public.yatanhasta (hasta_id, oda_id, yatistarihi, taburcutarihi)
VALUES
    (1, 1, '2026-05-01', NULL),
    (2, 3, '2026-05-05', NULL);

-- hemsire_yatanhasta (junction)
INSERT INTO public.hemsire_yatanhasta (hemsire_id, yatanhasta_id)
VALUES
    (1, 1),
    (2, 1),
    (3, 2);

-- ilac
INSERT INTO public.ilac (ilacadi, doz, ilactipi, ilacfiyat, uretimtarihi, sonkullanmatarihi)
VALUES
    ('Aspirin',      '100 mg', 'Analjezik',        5.50,  '2023-01-01', '2025-12-31'),
    ('Lisinopril',   '10 mg',  'Antihipertansif',  12.00, '2022-06-01', '2024-12-31'),
    ('Metformin',    '500 mg', 'Antidiyabetik',    8.75,  '2023-03-01', '2025-03-01'),
    ('Amoksisilin',  '250 mg', 'Antibiyotik',      15.00, '2022-09-01', '2024-09-01');

-- randevu
INSERT INTO public.randevu
    (hasta_id, doktor_id, randevutarihi, randevusaati, randevudurumu, notlar)
VALUES
    (1, 1, '2026-05-20', '10:00', 'Beklemede',   'Kontrol randevusu'),
    (2, 2, '2026-05-21', '14:00', 'Beklemede',   'İlk muayene'),
    (3, 3, '2026-04-15', '09:00', 'Tamamlandı',  'Nöroloji değerlendirmesi'),
    (4, 4, '2026-05-10', '16:00', 'Tamamlandı',  'Acil başvurusu');

-- ameliyat
INSERT INTO public.ameliyat
    (hasta_id, doktor_id, hemsire_id, ameliyatturu, ameliyattarihi, ameliyatsaati, sure, sonuc)
VALUES
    (1, 1, 1, 'Kalp Bypass',      '2026-05-02', '08:00', 180, 'Başarılı, komplikasyon yok.'),
    (4, 2, 2, 'Diz Artroskopisi', '2026-04-20', '10:30',  90, 'Başarılı, hasta stabil.');

-- tedavi (vezneucret_id set to NULL initially; updated after vezneucreti insert)
INSERT INTO public.tedavi
    (hasta_id, doktor_id, tedavituru, baslangictarihi, bitistarihi, aciklama, maliyet)
VALUES
    (1, 1, 'Kardiyovasküler Tedavi',     '2026-05-01', NULL,         'Bypass sonrası izlem tedavisi', 5000.00),
    (3, 3, 'Nörolojik Değerlendirme',    '2026-04-15', '2026-04-15', 'Baş ağrısı ve vertigo şikayeti', 800.00);

-- vezneucreti
INSERT INTO public.vezneucreti
    (hasta_id, tedavi_id, ucretturu, ucrettarihi, ucretmiktari, odemedurumu, odemetarihi)
VALUES
    (1, 1, 'Tedavi Ücreti',  '2026-05-01', 5000.00, 'Beklemede', NULL),
    (3, 2, 'Muayene Ücreti', '2026-04-15',  800.00, 'Ödendi',    '2026-04-15');

-- Link tedavi rows to their vezneucreti rows
UPDATE public.tedavi SET vezneucret_id = 1 WHERE tedavi_id = 1;
UPDATE public.tedavi SET vezneucret_id = 2 WHERE tedavi_id = 2;

-- rapor
INSERT INTO public.rapor (doktor_id, hasta_id, raporturu, tarih, icerik, sonuc)
VALUES
    (1, 1, 'Klinik Rapor',      '2026-05-01',
     'Hasta bypass ameliyatı sonrasında yoğun bakımda izlenmektedir.',
     'Genel durum iyi, vital bulgular stabil.'),
    (3, 3, 'Muayene Raporu',    '2026-04-15',
     'Hasta baş ağrısı ve denge bozukluğu şikayetiyle başvurdu. Nörolojik muayene normal.',
     'Akut patoloji saptanmadı. Kontrol önerildi.');

-- sevk
INSERT INTO public.sevk
    (hasta_id, doktor_id, sevkturu, sevknedeni, sevktarihi, sevksaati, sevkedilenyer)
VALUES
    (2, 2, 'Dahili Sevk', 'Ortopedi konsültasyonu', '2026-05-05', '09:00', 'Ankara Şehir Hastanesi');

-- tahlilvesonuclar
INSERT INTO public.tahlilvesonuclar (hasta_id, laboratuvar_id, doktor_id, tahlilturu, sonuc)
VALUES
    (1, 1, 1, 'Tam Kan Sayımı', 'Normal'),
    (3, 2, 3, 'Beyin MR',       'Belirgin patoloji yok');

-- asi
INSERT INTO public.asi (hasta_id, asituru, uygulamatarihi, hemsire_id)
VALUES
    (4, 'Tetanoz', '2026-01-15', 1),
    (5, 'Grip',    '2026-02-01', 2);

-- evrak
INSERT INTO public.evrak
    (hasta_id, personel_id, tedavi_id, evrakturu, evraktarihi, evrakaciklamasi, evrakdurumu)
VALUES
    (1, 4, 1, 'Tedavi Onay Formu', '2026-05-01', 'Bypass tedavisi için hasta onay formu.', 'Aktif'),
    (3, 4, 2, 'Reçete',            '2026-04-15', 'Baş ağrısı için ilaç reçetesi.',         'Aktif');

-- doktorilac (junction)
INSERT INTO public.doktorilac (doktor_id, ilac_id) VALUES (1, 1), (1, 2), (3, 3);

-- hastailac (junction)
INSERT INTO public.hastailac (hasta_id, ilac_id) VALUES (1, 1), (1, 2), (3, 3);

-- hastalaboratuvar (junction)
INSERT INTO public.hastalaboratuvar (hasta_id, laboratuvar_id) VALUES (1, 1), (3, 2);

-- hastaziyaretci
INSERT INTO public.hastaziyaretci (hasta_id, ad, soyad, ziyarettarihi)
VALUES
    (1, 'Kemal',  'Yılmaz', '2026-05-10'),
    (2, 'Seda',   'Kaya',   '2026-05-08');

-- ============================================================
-- SECTION 9: ROLES AND PERMISSIONS
-- ============================================================

DO $$
BEGIN
    -- yonetici_rol: full access
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'yonetici_rol') THEN
        CREATE ROLE yonetici_rol;
    END IF;
    -- doktor_rol: read all; write clinical tables
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doktor_rol') THEN
        CREATE ROLE doktor_rol;
    END IF;
    -- hemsire_rol: read most; write nursing tables
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hemsire_rol') THEN
        CREATE ROLE hemsire_rol;
    END IF;
    -- vezne_rol: read/write billing and documents; read patients and treatments
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vezne_rol') THEN
        CREATE ROLE vezne_rol;
    END IF;
END
$$;

-- yonetici_rol: ALL on all tables and sequences
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO yonetici_rol;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO yonetici_rol;

-- doktor_rol: SELECT everywhere; INSERT/UPDATE on clinical tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO doktor_rol;
GRANT INSERT, UPDATE ON
    public.randevu, public.rapor, public.tedavi,
    public.ameliyat, public.tahlilvesonuclar,
    public.sevk, public.doktorilac
TO doktor_rol;
GRANT USAGE ON SEQUENCE
    public.randevu_randevu_id_seq,
    public.rapor_rapor_id_seq,
    public.tedavi_tedavi_id_seq,
    public.ameliyat_ameliyat_id_seq,
    public.tahlilvesonuclar_tahlilvesonuclar_id_seq,
    public.sevk_sevk_id_seq,
    public.doktorilac_doktorilac_id_seq
TO doktor_rol;

-- hemsire_rol: SELECT everywhere; INSERT/UPDATE on nursing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO hemsire_rol;
GRANT INSERT, UPDATE ON
    public.asi, public.hemsire_yatanhasta
TO hemsire_rol;
GRANT USAGE ON SEQUENCE
    public.asi_asi_id_seq,
    public.hemsire_yatanhasta_id_seq
TO hemsire_rol;

-- vezne_rol: read/write billing & documents; read patients and treatments
GRANT SELECT ON
    public.hasta, public.tedavi, public.sigorta,
    public.doktor, public.bolum
TO vezne_rol;
GRANT SELECT, INSERT, UPDATE ON
    public.vezneucreti, public.evrak
TO vezne_rol;
GRANT USAGE ON SEQUENCE
    public.vezneucreti_vezneucreti_id_seq,
    public.evrak_evrak_id_seq
TO vezne_rol;

COMMIT;
