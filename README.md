# Hospital Management System — PostgreSQL Database

A relational database schema for managing hospital operations including patients, doctors,
appointments, treatments, surgeries, medications, laboratories, and billing.

## Setup

### Prerequisites

- PostgreSQL 10 or later (ENUM types, triggers, and views used here are supported since PostgreSQL 9.1; version 10+ is recommended for security and performance)

### Create and load the database

```bash
createdb hospital_db
psql -U postgres -d hospital_db -f hospital.sql
```

### Verify the installation

```sql
-- list all tables
\dt public.*

-- check sample data
SELECT COUNT(*) FROM hasta;          -- 5 patients
SELECT * FROM aktif_randevular;      -- upcoming appointments
SELECT * FROM oda_doluluk;           -- room occupancy
SELECT * FROM doktor_ameliyat_sayisi;
```

---

## Table Reference

| Table (Turkish)       | English                  | Description                                      |
|-----------------------|--------------------------|--------------------------------------------------|
| `ameliyat`            | Surgery                  | Surgical procedure records                       |
| `asi`                 | Vaccination              | Patient vaccination records                      |
| `bolum`               | Department               | Hospital departments                             |
| `doktor`              | Doctor                   | Doctor profiles                                  |
| `doktorilac`          | Doctor–Medication         | Which drugs each doctor prescribes (M:N)         |
| `evrak`               | Document                 | Medical documents and administrative forms       |
| `hasta`               | Patient                  | Patient personal and medical information         |
| `hastailac`           | Patient–Medication        | Medications assigned to patients (M:N)           |
| `hastalaboratuvar`    | Patient–Laboratory        | Patient-to-laboratory associations (M:N)         |
| `hastaziyaretci`      | Visitor                  | Visitors recorded for inpatients                 |
| `hemsire`             | Nurse                    | Nurse profiles                                   |
| `hemsire_yatanhasta`  | Nurse–Inpatient           | Nurse-to-inpatient care assignments (M:N)        |
| `ilac`                | Medication               | Medication / drug catalog                        |
| `laboratuvar`         | Laboratory               | Laboratory departments                           |
| `oda`                 | Room                     | Hospital rooms                                   |
| `personel`            | Staff                    | Administrative and support staff                 |
| `randevu`             | Appointment              | Doctor–patient appointments                      |
| `rapor`               | Report                   | Medical reports                                  |
| `sevk`                | Referral                 | Patient referrals to other facilities/departments|
| `sigorta`             | Insurance                | Patient insurance policies                       |
| `tahlilvesonuclar`    | Test Results             | Lab tests and their outcomes                     |
| `tedavi`              | Treatment                | Treatment records                                |
| `vezneucreti`         | Billing / Cashier Fee    | Patient billing records                          |
| `yatanhasta`          | Inpatient                | Admitted (hospitalized) patient records          |

---

## ENUM Types

| Type              | Values                                                                    |
|-------------------|---------------------------------------------------------------------------|
| `randevu_durumu_t`| `Beklemede`, `Tamamlandı`, `İptal`, `Gelmedi`                             |
| `evrak_durumu_t`  | `Aktif`, `Arşivlendi`, `İptal`                                            |
| `odeme_durumu_t`  | `Ödendi`, `Beklemede`, `İptal`                                            |
| `bolum_tipi_t`    | `Acil`, `Dahiliye`, `Cerrahi`, `Kardiyoloji`, `Nöroloji`, `Onkoloji`, ... |
| `cinsiyet_t`      | `E` (Male), `K` (Female)                                                  |
| `kan_grubu_t`     | `A+`, `A-`, `B+`, `B-`, `AB+`, `AB-`, `O+`, `O-`                         |

---

## Views

| View                    | Description                                              |
|-------------------------|----------------------------------------------------------|
| `aktif_randevular`      | Pending appointments (`Beklemede`) on or after today     |
| `yatan_hastalar`        | Current inpatients with room details and assigned nurses |
| `odenmemis_ucretler`    | Unpaid billing records (`Beklemede`)                     |
| `doktor_ameliyat_sayisi`| Surgery count per doctor                                 |
| `oda_doluluk`           | Live room occupancy (replaces the removed `oda.dolu` column) |

---

## Key Design Decisions

### Audit columns
Every table has `olusturulma_tarihi` (created_at) and `guncelleme_tarihi` (updated_at),
both with `DEFAULT NOW()`. A `BEFORE UPDATE` trigger automatically refreshes
`guncelleme_tarihi` on every row update.

### Room occupancy
The old `oda.dolu` boolean has been removed because it was a denormalised derived value
that could silently go out of sync. Use the `oda_doluluk` view instead — it computes
current occupancy and free beds dynamically from the `yatanhasta` table.

### Nurse–inpatient assignments
The old `hemsire.yatanhasta_id` column only allowed a nurse to be linked to one inpatient.
It has been replaced by the `hemsire_yatanhasta` junction table, which supports M:N
assignments (one nurse can care for many inpatients; one inpatient can have many nurses).

### Medication relationships
`ilac` is a medication catalog. The redundant `doktor_id` and `hasta_id` columns have
been removed from `ilac`; relationships are now expressed exclusively through the
`doktorilac` and `hastailac` junction tables.

### Department head
`bolum.bolumsorumlusu_id` is a foreign key to `personel`, replacing the old free-text
varchar column and enforcing referential integrity.

### Foreign-key delete behaviour
Most FK columns referencing `hasta` (patient) use `ON DELETE CASCADE` so that all records
are cleaned up when a patient is removed. References to staff (doktor, hemsire, personel)
use `ON DELETE SET NULL` to preserve historical records after a staff member leaves.
The `hastalaboratuvar.laboratuvar_id` FK uses `ON DELETE RESTRICT` — a laboratory cannot
be deleted while patient associations exist, since those associations carry historical
diagnostic significance.
Both `tedavi.vezneucret_id` and `vezneucreti.tedavi_id` are nullable. When inserting
linked pairs, insert `tedavi` first (with `vezneucret_id = NULL`), then `vezneucreti`,
then `UPDATE tedavi SET vezneucret_id = ...`.

---

## ER Diagram Overview

```
sigorta ─< hasta >─ yatanhasta >─ oda
                  |
          randevu, evrak, rapor, sevk,
          tedavi ─ vezneucreti,
          ameliyat, asi, ilac (via hastailac),
          tahlilvesonuclar (via hastalaboratuvar),
          hastaziyaretci

doktor >─ bolum (bolumsorumlusu_id → personel)
doktor ─< ameliyat, randevu, rapor, sevk,
          tedavi, tahlilvesonuclar, ilac (via doktorilac)

hemsire ─< ameliyat, asi
hemsire ─< hemsire_yatanhasta >─ yatanhasta

laboratuvar ─< tahlilvesonuclar
             ─< hastalaboratuvar
```

---

## Database Roles

| Role           | Permissions                                                                             |
|----------------|-----------------------------------------------------------------------------------------|
| `yonetici_rol` | ALL PRIVILEGES on all tables and sequences                                              |
| `doktor_rol`   | SELECT on all tables; INSERT/UPDATE on `randevu`, `rapor`, `tedavi`, `ameliyat`, `tahlilvesonuclar`, `sevk`, `doktorilac` |
| `hemsire_rol`  | SELECT on all tables; INSERT/UPDATE on `asi`, `hemsire_yatanhasta`                      |
| `vezne_rol`    | SELECT on `hasta`, `tedavi`, `sigorta`, `doktor`, `bolum`; SELECT/INSERT/UPDATE on `vezneucreti`, `evrak` |

Assign a role to a database user:
```sql
GRANT doktor_rol TO my_doctor_user;
```
