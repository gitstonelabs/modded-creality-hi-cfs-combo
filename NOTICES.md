# Notices

This file records where everything in this repository came from and what license covers it. The short version: the repo's own work is GPL-3.0, the software it installs is GPL-3.0, and the bundled vendor documents stay under whatever terms their vendors published them with.

## This repository

Everything original to this repository is licensed under the GNU General Public License v3.0. The full text is in [LICENSE](LICENSE). That covers:

- The Klipper config set in `config/` (`printer.cfg`, `ebb42.cfg`, `nebula.cfg`, `eddy.cfg`, `cfs.cfg`, `macros.cfg`), authored for this build.
- The install scripts in `scripts/`.
- The documentation: `README.md`, `INSTALL.md`, and the guides under `docs/` (excluding the vendor material in `docs/hardware/`, covered below).

GPL-3.0 was chosen to match the CFS driver this repo installs.

## creality-cfs-klipper (installed by the scripts, not vendored)

The CFS is driven by the `creality_cfs` Klipper module from:

- Repository: https://github.com/gitstonelabs/creality-cfs-klipper
- License: GPL-3.0
- Pinned commit: `73731e9` (v1.4.0)

`scripts/install.sh` clones that repository at the pinned commit and copies `src/creality_cfs.py` into the host's `~/klipper/klippy/extras/`. No source from that repository is redistributed inside this one. Its license and copyright notices live in the repository itself.

## Klipper

The configs in `config/` are configuration for [Klipper](https://github.com/Klipper3d/klipper), and the installer copies one module into a user's existing Klipper install. Klipper is GPL-3.0, copyright Kevin O'Connor and contributors. This repository does not distribute Klipper.

## Vendor hardware documents (`docs/hardware/`)

The files under `docs/hardware/` are the hardware vendors' own published materials (schematics, pinout diagrams, manuals, sample configs), copied unmodified from their public repositories. They are included so a builder can wire and flash the boards without hunting down five separate repos. They are **not** covered by this repository's GPL-3.0 license; each stays under its original terms:

| Product | Vendor | Source | Terms |
|---|---|---|---|
| EBB42 CAN V1.0 / Gen2 toolhead board | BIGTREETECH | https://github.com/bigtreetech/EBB | No license file in the source repo; copyright remains with BIGTREETECH |
| Eddy / Eddy Duo probe | BIGTREETECH | https://github.com/bigtreetech/Eddy | No license file in the source repo; copyright remains with BIGTREETECH |
| Octopus V1.0 mainboard | BIGTREETECH | BIGTREETECH's published Octopus V1.0 repository (github.com/bigtreetech) | No license file in the source repo; copyright remains with BIGTREETECH |
| S2DW V1.0 accelerometer | BIGTREETECH | https://github.com/bigtreetech/LIS2DW | No license file in the source repo; copyright remains with BIGTREETECH |
| Nebula smart extruder | BIQU | https://github.com/bigtreetech/Nebula (wiki: https://bttwiki.com/Nebula.html) | CC BY-NC-ND 4.0, copyright (c) 2025 BIQU |

Note on the Nebula material: CC BY-NC-ND 4.0 permits redistribution with attribution but forbids modification and commercial use. The Nebula documents here are verbatim copies, attributed above.

If any vendor objects to their material being mirrored here, open an issue and it will be replaced with links.

## Stock Creality configs (`reference/stock-hi/`)

The files under `reference/stock-hi/` are the factory Klipper configuration files pulled from a stock Creality Hi. They are Creality's material, included unmodified for provenance: they document what the mainline config set in `config/` replaced, and they are the ground truth for stock-faithful behavior like the cutter sequence. They are not covered by this repository's GPL-3.0 license and carry no license grant from this repository.

## Trademarks

Creality, CFS, BIGTREETECH, BIQU, Octopus, EBB, Eddy, and Nebula are names of their respective owners, used here only to identify the hardware this build runs on. This project is not affiliated with or endorsed by Creality, BIGTREETECH, or BIQU.
