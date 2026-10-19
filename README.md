# AeroJudge Device Scripts

This repository maintains device setup, update and recovery scripts, boot config
profiles and assets, including wallpaper. The app repository retains compatibility entry points
for existing base images and installed devices.

## NEW Device Setup Procedure

See [SETUP.md](SETUP.md) for supported hardware, installation steps, settings, version checks, and post-reboot validation.

Legacy setup instructions are in [README_legacy.md](README_legacy.md).

## Repository ownership and compatibility

Executable setup/maintenance scripts live at the repository root. Wallpaper lives
in `assets/`; legacy test data is in `assets/legacy/data.zip`.

Configuration files are maintained in `config/profiles/`. These have specific options for each base hardware configuration.  


Several services and launchers remain in the repositories they serve, such as judge/kiosk services in the `aerojudge-device-app` repo and volume services in the `device-volume-svc` repo. 

The `aerojudge-device-app` repository retains two forwarding links for
`scripts/judge_setup.sh` and `scripts/judge_update.sh` that point to this repository
to support existing devices. 
