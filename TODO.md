# TODO

- **Fix clipped screenshots** – Some plug-in GUIs are still captured with parts
  missing or extra chrome. Investigate plug-in view sizing and make the capture
  rectangles resilient across frameworks.
- **Repair `--delete-unsupported` flag** – The sweep script should reliably
  delete Intel-only bundles when requested. Reproduce the failure and ensure the
  architecture warning detection is robust.
- **Testing** – Add unit tests for the host logic (e.g., ScreenshotHost helpers)
  and an integration test harness that exercises the CLI against stub plug-ins.
