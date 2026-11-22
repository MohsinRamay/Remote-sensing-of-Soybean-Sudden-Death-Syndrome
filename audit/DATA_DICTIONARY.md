# Initial data dictionary

The [column inventory](tables/column_profiles.csv) gives the exact header, position, imported R type, missingness, distinct count and numeric range for every source column. The [file inventory](tables/inventory.csv) records dates, dimensions and SHA-256 hashes. The table below documents field meaning and evidence.

| Source fields | Meaning and units | Evidence and limitations |
|---|---|---|
| `DATE` | Reflectance acquisition date, calendar day | Workbook and CSV encodings include Excel dates, Excel serials and month/day/year text. Time of day and acquisition order are unavailable. |
| `Date`, `Doy`, `YYYY-MM-DD_Incidence`, `YYYY-MM-DD_Severity` | Disease assessment calendar date. `Doy` contains ISO dates. | Joined export headers date the ratings independently of the reflectance date in each row. |
| `Block` | Recorded block label | Dissertation chapters 2–3 describe four Marsden and six Hinds blocks. Keep year and site with block labels. |
| `Plot` | Recorded plot identifier, treated as a label | Marsden 2016–2018 uses a main-plot label candidate. Hinds uses the trial microplot label. Marsden 2019's `Plot` contains 240 distinct values and serves as a spectrum identifier with `Quadrat`. Its mapping to main plots needs verification. Some Hinds 2018 workbook cells contain fractional plot values. |
| `Quadrat` | Marsden subsample identifier, treated as a label | Dissertation chapters 2–3 describe 3 m × 1.5 m quadrats, nominally 20 per sampled soybean plot. The number actually represented varies by year and data stream. |
| `Rotation` | Recorded Marsden cropping-system code | S2, S3 and S4 denote soybean phases of the 2-, 3- and 4-year cropping systems. Systems differ in crop sequence and fertility management. Dissertation chapter 3 describes main plots and subplots. Source-specific label conflicts and physical plot continuity need field verification. |
| `Treatment`, `Variety`, `Conc`, `Concentration` | Hinds treatment code, cultivar and nominal dose | Dissertation and Hinds experiment sheet document the 2018 two-cultivar × five-dose design. Codes 1 and 2 refer to Pioneer P20T79R2 and Syngenta NK Soybean S24-K2. Source dose units are mL per linear foot of row in 2018. Confirm the zero-dose carrier and the 2019 key before interpreting those records. |
| `Reading` | 2018 reading label | Hinds notebook takes the first three digits as plot. Conflicts with the `Plot` field and repeated reading labels are flagged. The repeat suffix and acquisition order are undocumented. |
| `Wavelength`, `W460` through `W810` | Eight band centers in nm, or recorded reflectance at the band in a wide workbook | Verified in the project notebook and tabular headers. Bandwidths and instrument configuration remain unknown. |
| `Reflectance` | Stored canopy reflectance value at a band center | Scale, reference procedure and calibration remain unknown. Earlier workflow describes nominally two readings per unit and averages by date and metadata. The 2018 files include departures from two readings. |
| `Incidence` | Percentage of plants showing foliar symptoms within the quadrat or microplot | Dissertation §2, pp. 37–38, and §3, p. 70. Repository CSVs carry percentages without counts or denominators. An archived Hinds field workbook holds early counts and a stand estimate. Confirm extrapolation, recounts and later visual estimates before using a count model. |
| `Severity` | Estimated percentage of quadrat or microplot area with chlorotic to necrotic foliar symptoms | Dissertation §2, pp. 37–38, and §3, p. 70. Confirm rounding, trace-score rules and any field-specific changes in practice. |
| `Yield` | In Hinds, a plot harvest value copied onto each rating and repeated in the joined export | Archived combine workbook labels the matching values bu/ac. The repository's numerical values are linked to different plot labels in the two versions. Dissertation describes publication units of kg/ha, middle two rows harvested, and adjustment to 13% moisture. Marsden harvest is in separate archive files. Verify field-to-harvest linkage before joining. |
| `ID` | Marsden disease season label | Values `SDS_2016`, `SDS_2017` and `SDS_2018`. |
| Unnamed CSV columns | Exported row index or a trailing all-empty column | Detected by index and type in the column profiles. They have no measurement role. |

## Experimental hierarchy

| Trial | Design supported by study documentation | Repeated observations |
|---|---|---|
| Marsden 2016–2018 | Site → four blocks → cropping-system main plots. Nine main plots per block across all phases, three soybean main plots per block in each disease-linked season. The dissertation also describes two subplots within a main plot. Their assignment and linkage to sampled quadrats need the field map. | Candidate plot-year → quadrat subsample → assessment or acquisition date → measurement, band or reading. Main plots are the candidate experimental units for the cropping-system contrast. |
| Hinds 2018 | Site → six blocks → ten randomized treatment microplots per block. The experiment sheet records the realized cultivar and dose assignments. | Microplot → date → rating or band/reading. Yield is a single harvest endpoint. Separately tagged border plants in the SDS Paper study represent a different cohort. |
| Hinds and Marsden 2019 | Reflectance-only scope. Marsden uses `Quadrat + Plot` to distinguish spectral trajectories. | Keep identifiers within site and year. Confirm physical-plot and treatment crosswalks before pooling or transferring across years. |

Candidate observational keys are `site / year / unit`, plus actual date for visits and band for spectra. Site/year/block/plot is the candidate main-plot or microplot label; repeated numeric labels in the [cross-season table](tables/reused_plot_labels.csv) need physical coordinates and crop-phase history before use as longitudinal plot identifiers.
