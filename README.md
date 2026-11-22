# OnyxOS 1.0 (Plasma Edition)

Distribution live basée sur Fedora KDE (noyau Fedora, paquets Fedora, KDE
Plasma), avec une identité 100 % OnyxOS : GRUB, Plymouth, SDDM/plasmalogin,
KDE (thème, fond d'écran, écran d'accueil), `/etc/os-release`, logos.

## Construire l'ISO

Prérequis :

- Windows 10/11 avec **WSL 2** (Ubuntu) et les paquets
  `xorriso erofs-utils python3-pil` ;
- Python 3 avec Pillow côté Windows (génération des assets) ;
- l'ISO source `Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso` à la racine.

```powershell
# Tout-en-un : assets, audit, build, lancement QEMU
.\build-and-run.ps1

# Ou uniquement le build (passe par WSL en root)
python build_iso.py
```

L'ISO est écrite dans `OnyxOS-1.0-live-x86_64.iso` avec son `.sha256`.

## Tester dans QEMU

```powershell
.\run-test.ps1                 # fenêtre QEMU
.\run-test.ps1 -Headless       # sans affichage, log série qemu-boot.log
.\launch-onyxos.ps1            # raccourci
```

Le lanceur utilise un CD **virtio-scsi** (l'IDE de QEMU provoquait des erreurs
de lecture EROFS avec une ISO > 4 Go), `-machine q35`, `-cpu max` et
`-accel tcg,thread=multi`.

## Ce que fait le rebranding

`rebuild-live-iso.sh` :

1. extrait l'ISO et la racine EROFS (`erofsfuse`, xattrs SELinux préservés) ;
2. remplace `/usr/lib/os-release`, `/etc/os-release`, `/etc/system-release`,
   `/etc/redhat-release`, `/etc/issue`, `/etc/motd` et le hostname ;
3. installe les thèmes KDE, le fond d'écran, les logos, le look-and-feel
   `org.onyxos.desktop` et l'autostart `onyxos-desktop-setup` ;
4. embarque le thème Plymouth `onyxos` (plugin `two-step`, le plugin `script`
   n'existe pas dans l'image Fedora) dans l'initramfs via `dracut` ;
5. reconstruit le squashfs EROFS (labels SELinux via `--file-contexts`) ;
6. rebrande GRUB (libellés, `CDLABEL`, `console=tty0/ttyS0`, `noapic`,
   masques ABRT, rendu Qt logiciel) et re-scelle l'ISO avec xorriso.

## Résultat vérifié

- GRUB : `screenshots/grub-boot.png` ;
- démarrage live jusqu'au login : `screenshots/boot-login.txt` ;
- session Plasma démarrée (KWin Wayland, plasmashell, session `liveuser` sur
  `seat0`).

## Limites connues

- **Rendu graphique sous QEMU TCG** : le GPU émulé (bochs/virtio sans virgl)
  n'expose pas d'EGL utilisable par KWin. La session Plasma démarre mais le
  framebuffer reste noir. Sur du matériel réel (ou QEMU avec virgl/GPU) le
  bureau s'affiche. Le login reste accessible sur `ttyS0`.
- `noapic`, les masques ABRT et le rendu Qt logiciel sont ajoutés à la ligne
  de commande noyau pour la compatibilité QEMU/TCG. Ils sont sans effet notable
  sur un live réel, mais peuvent être retirés pour un usage matériel.
- L'installateur Anaconda embarqué conserve son habillage Fedora ; le système
  live et le bureau sont, eux, entièrement OnyxOS.
- L'ISO pèse ~5,4 Go (racine 8,2 Go compressée en lz4hc).

## Arborescence

```
assets/              logos, fonds d'écran, Plymouth, SDDM
config/              os-release, kcm-about-distrorc
theme/               OnyxDark.colors, OnyxKonsole.colorscheme
screenshots/         preuves de boot (GRUB, login série)
build_iso.py         orchestrateur Windows -> WSL
rebuild-live-iso.sh  build complet du live ISO
build-and-run.ps1    pipeline assets + build + QEMU
build-auto.sh        pipeline Linux équivalent
run-test.ps1         lanceur QEMU
launch-onyxos.ps1    raccourci de lancement
onyxos-kde.ks        recette Kickstart de référence (non utilisée par le build)
```
