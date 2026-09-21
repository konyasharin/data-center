# Сборка ассетов

Полное описание — `docs/14-art-assets.md`.

```bash
BLENDER="/c/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe"

"$BLENDER" -b --factory-startup --python tools/blender/build_all.py
"$BLENDER" -b --factory-startup --python tools/blender/build_rack.py
python tools/verify_assets.py
```

`--factory-startup` обязателен: сборка не должна зависеть от настроек и аддонов
конкретной машины.
