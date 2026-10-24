"""AppModel を小さな一時パッケージにコピーし、通信せずに天気更新を検証する。"""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="astera-weather-") as directory:
    package = Path(directory)
    (package / "Sources/WeatherAppModel").mkdir(parents=True)
    (package / "Tests/WeatherAppModelTests/Fixtures").mkdir(parents=True)
    (package / "Sources/WeatherAppModel/AppModel.swift").write_bytes((root / "App/AppModel.swift").read_bytes())
    (package / "Tests/WeatherAppModelTests/WeatherOfflineTests.swift").write_bytes(
        (root / "scripts/tests/WeatherOfflineTests.swift").read_bytes())
    (package / "Tests/WeatherAppModelTests/Fixtures/open_meteo_sample.json").write_bytes(
        (root / "Packages/StarCore/Tests/StarCoreTests/Fixtures/open_meteo_sample.json").read_bytes())
    core_path = json.dumps(str(root / "Packages/StarCore"))
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WeatherAppModel", platforms: [.macOS(.v15)],
    dependencies: [.package(path: CORE_PATH)],
    targets: [
        .target(name: "WeatherAppModel", dependencies: [.product(name: "StarCore", package: "StarCore")]),
        .testTarget(name: "WeatherAppModelTests", dependencies: ["WeatherAppModel"],
                    resources: [.copy("Fixtures")])
    ])
'''.replace("CORE_PATH", core_path))
    subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
