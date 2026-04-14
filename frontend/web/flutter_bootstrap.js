{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Use local CanvasKit files to avoid external gstatic dependency.
    canvasKitBaseUrl: "/canvaskit/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: "{{flutter_service_worker_version}}",
  },
});
