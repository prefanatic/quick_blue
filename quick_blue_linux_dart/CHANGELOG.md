## 0.5.0

- Extract the existing BlueZ/D-Bus/L2CAP implementation and lifecycle regressions
  from `quick_blue_linux` without behavioral changes. Reuse core and platform
  interface state; retain the `QuickBlueLinux` class and cooperative lease names.
- Support standalone Dart without Flutter SDK constraints or plugin metadata.
  Flutter consumers continue to use the `quick_blue_linux` registration shell.
