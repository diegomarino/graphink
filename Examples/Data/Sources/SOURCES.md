# Raw source data

These files are exact downloads from the official sites, retrieved 2026-11-15 (UTC)
with `curl`. `Examples/Data/prepare.py` reads only these files, and the validator
recomputes every plotted value from them. Nothing was read off a third-party chart.

## `aeat-irpf-2024/`: AEAT, Estadística de los declarantes del IRPF 2024

| File | Table | URL |
| --- | --- | --- |
| `435-base-imponible-general.html` | Partida 435, Base imponible general, por tramos de rendimiento, tipo de declaración Total | `https://sede.agenciatributaria.gob.es/AEAT/Contenidos_Comunes/La_Agencia_Tributaria/Estadisticas/Publicaciones/sites/irpf/2024/jrubikb6f7328b002b470185289a491310915e897e4a9.html` |
| `460-base-imponible-ahorro.html` | Partida 460, Base imponible del ahorro, same layout | `…/sites/irpf/2024/jrubikf12af38eebb550ce5ffd9f2c37d357ab15fba43a5.html` |
| `595-cuota-resultante.html` | Partida 595, Cuota resultante de la autoliquidación, same layout | `…/sites/irpf/2024/jrubik6e70e04673a9197608f95196acaae2c24f9a7113.html` |
| `condiciones-reutilizacion.html` | AEAT reuse conditions | `https://sede.agenciatributaria.gob.es/Sede/gobierno-abierto/reutilizacion-informacion/condiciones-reutilizacion.html` |

The navigation path is Estadística de los declarantes del IRPF 2024 ▸ Estadística por
partidas ▸ Por tramos de rendimiento. The exercise is 2024, and the methodology
(`…/sites/irpf/2024/docs/irpf/markoff_metod_irpf2024.pdf`) is dated **01/07/2026**.
datos.gob.es lists the catalogue entry `ea0028512-estadistica-de-los-declarantes-del-impuesto-sobre-la-renta-de-las-personas-fisicas-irpf`
as modified on 30 June 2026.

- **Grouping (resolved).** The tables use ten "tramos de rendimientos e imputaciones de
  renta". The methodology defines the classification variable as
  "Base imponible general + Base imponible del ahorro estando las bases imponibles
  acotadas a 0". The brackets are therefore taxable-base brackets with negatives floored
  at zero, and the bracket limits are in € thousands.
- **Columns used.** "Liquidaciones Número Total" counts all returns in the bracket and
  is identical in all three tables. "Importe partida" is the amount in euros.
- **Coverage.** The statistic covers the Territorio de Régimen Fiscal Común, so it
  excludes the País Vasco and Navarra and includes Ceuta and Melilla. It covers returns
  filed, not all residents.
- **Terms.** AEAT uses the basic mode without specific conditions (art. 8.1 RD
  1495/2011), under the reuse framework of Ley 37/2007, which covers commercial and
  non-commercial reuse. The conditions are: do not distort the meaning; cite AEAT;
  give the date of last update when the original has one; do not suggest AEAT
  endorsement; keep any update-date and reuse metadata.
- **Credit used.** "Fuente: AEAT, Estadística de los declarantes del IRPF 2024
  (actualizada el 01/07/2026); elaboración propia".

## `ine/`: INE series (JSON from the INE Tempus 3 API)

| File | Series | Table | URL |
| --- | --- | --- | --- |
| `IPV769.json` | Índice de Precios de Vivienda, Nacional, General, Índice (base 2015), quarterly 2007T1–2025T4 | 25171 | `https://servicios.ine.es/wstempus/js/ES/DATOS_SERIE/IPV769?date=20070101:20271231` |
| `ETCL1527.json` | ETCL, Ambas jornadas, Industria, construcción y servicios, Coste salarial total por trabajador y mes, Total Nacional, euros, not seasonally adjusted, quarterly 2008T1–2026T2 | 6038 | `…/DATOS_SERIE/ETCL1527?date=20070101:20271231` |
| `IPC251852.json` | IPC, Nacional, Índice general, Índice (base 2021), monthly 2007M01–2025M12 | 50902 | `…/DATOS_SERIE/IPC251852?date=20070101:20271231` |
| `aviso-legal-reutilizacion.txt` | Exact text extract of the reuse section of the INE legal notice | — | `https://www.ine.es/ss/Satellite?L=es_ES&c=Page&cid=1254735849170&p=1254735849170&pagename=Ayuda%2FINELayout` |

In the API, `FK_Periodo` 19–22 means quarters T1–T4, and 1–12 means months.

- **Terms.** INE allows commercial and non-commercial reuse of INE-sourced information
  if the meaning is not distorted, the source is cited, the date of last update is given
  where the original has one, and INE endorsement is not suggested. The legal notice
  does not name a Creative Commons licence.
- **Credit used.** "Elaboración propia con datos extraídos del sitio web del INE: www.ine.es".
  The latest periods used are IPV 2025T4 and IPC 2025M12. The ETCL file runs to 2026T2,
  but only the quarters shared with the IPV are plotted.

## `oecd-revenue-statistics/`: OECD Revenue Statistics, Spain

| File | Content |
| --- | --- |
| `ESP-total-tax-revenue-pct-gdp.csv` | Exact SDMX API response: dataflow `OECD.CTP.TPS:DSD_REV_COMP_OECD@DF_RSOECD(2.0)` ("Revenue Statistics in OECD member countries - Comparative tax revenues"), key `ESP.TAX_REV.S13._T._T.PT_B1GQ.A` (Spain, tax revenue, general government, total tax revenue, % of GDP, annual), 60 observations 1965–2024, all `OBS_STATUS` A (normal value). URL `https://sdmx.oecd.org/public/rest/data/OECD.CTP.TPS,DSD_REV_COMP_OECD@DF_RSOECD,2.0/ESP.TAX_REV.S13._T._T.PT_B1GQ.A?format=csvfilewithlabels` |
| `http-headers.txt` | Response `date` and `last-modified: 2025-12-09`, which places the data in the Revenue Statistics 2025 edition |
| `dataflow-DF_RSOECD-2.0.json` | Dataflow structure (`https://sdmx.oecd.org/public/rest/dataflow/OECD.CTP.TPS/DSD_REV_COMP_OECD@DF_RSOECD/2.0`) |
| `oecd-terms-data-2026-11-15.txt` | Section "3. Data" of `https://www.oecd.org/en/about/terms-conditions.html`, copied verbatim in a browser on 2026-11-15 (the page refuses automated requests) |

- **Terms.** Data may be extracted, adapted and distributed for any purpose, including
  commercial use, except where the metadata shows third-party ownership or extra
  restrictions.
- **Metadata check (2026-11-15, SDMX API only).** No third-party ownership, extra
  restriction, source note or dataset-specific citation was found:
  - The dataflow description has none.
  - The structure has no licence, rights, source or citation annotation; text matches
    for "owner" and "restrict" are only revenue-category names.
  - The DSD attributes are `OBS_STATUS`, `UNIT_MULT`, `REVENUE_CODE`, `DECIMALS` and
    `CURRENCY`, and the series' values are "Normal value", "Units", "TOTALTAX", "One"
    and "Not applicable".
  - The API's reference-metadata endpoints return 404/403, so the Data Explorer
    "source" tab text could not be read this way.
- **Citation** (terms format, no dataset-specific one available): "OECD (2025),
  Revenue Statistics in OECD member countries - Comparative tax revenues, OECD Data
  Explorer, https://sdmx.oecd.org/public/rest/data/OECD.CTP.TPS,DSD_REV_COMP_OECD@DF_RSOECD,2.0/ESP.TAX_REV.S13._T._T.PT_B1GQ.A
  (accessed on 15 November 2026)."
- **Sub-licence clause.** Anyone who shares or licenses work created with these data
  must include the same acknowledgment requirement in any sub-licence and require
  further sub-licensees to do the same. This applies to the document, its manifest
  credits and any future public repository.
- **Values.** The chart plots the published values exactly, with no transformation.
