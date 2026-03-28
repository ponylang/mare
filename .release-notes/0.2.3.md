## Fix crash when dispose() arrives before connection initialization

Calling `dispose()` on a connection actor before its initialization completed could crash. The race was unlikely but was observed on macOS arm64.

