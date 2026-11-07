#!/usr/bin/env python3
"""Run standalone regression suites in Swift 6 mode without changing live devices."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
import platform
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "build/swift6-tests"


def run_suite(test, sources, stub):
    folder = OUTPUT / test.stem
    folder.mkdir(exist_ok=True)
    (folder / "verification").mkdir(exist_ok=True)
    binary = folder / test.stem
    inputs = sources + [str(test)]
    if "enum SettingsWindow" not in test.read_text():
        inputs.append(str(stub))
    command = ["xcrun", "swiftc", "-target", f"{platform.machine()}-apple-macosx26.0",
               "-swift-version", "6", "-strict-concurrency=complete",
               "-Onone", "-parse-as-library", *inputs, "-o", str(binary)]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    log = result.stdout + result.stderr
    status = "compile-failed"
    if result.returncode == 0:
        cases = ["login", "location", "menu"] if test.stem == "ReviewRegressionTests" else [str(folder / "artifacts")]
        status = "passed"
        for case in cases:
            try:
                result = subprocess.run([str(binary), case], cwd=folder, capture_output=True, text=True, timeout=90)
                log += result.stdout + result.stderr
                if result.returncode:
                    status = "skipped" if test.stem == "MenuBarCensusBackgroundTests" and result.returncode == 2 else "failed"
                    break
            except subprocess.TimeoutExpired as error:
                log += f"Timed out: {error}\n"
                status = "failed"
                break
    (folder / "result.log").write_text(log)
    return {"suite": test.stem, "status": status, "log": str(folder / "result.log")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", action="append", help="Run a named suite; may be repeated")
    options = parser.parse_args()
    tests = sorted((ROOT / "HaspTests").glob("*.swift"))
    if options.suite:
        tests = [test for test in tests if test.stem in options.suite]
        if set(options.suite) != {test.stem for test in tests}:
            sys.exit("Unknown suite name")
    if not tests:
        sys.exit("No test suites found")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "verification").mkdir(exist_ok=True)
    stub = OUTPUT / "SettingsWindowStub.swift"
    stub.write_text("@MainActor enum SettingsWindow { static func show(model: AppModel) {} }\n")
    sources = sorted(str(p) for p in (ROOT / "Hasp").glob("*.swift") if p.name != "HaspApp.swift")
    results = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        jobs = [pool.submit(run_suite, test, sources, stub) for test in tests]
        for job in as_completed(jobs):
            result = job.result()
            results.append(result)
            print(f"{result['status']}: {result['suite']}", flush=True)
    report = {"compiler": subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip(),
              "developerDirectory": os.environ.get("DEVELOPER_DIR", "system default"),
              "baseCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "results": sorted(results, key=lambda value: value["suite"])}
    (OUTPUT / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Report: {OUTPUT / 'results.json'}")
    if any(result["status"] not in ("passed", "skipped") for result in results):
        sys.exit(1)


if __name__ == "__main__":
    main()
