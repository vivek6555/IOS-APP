import unittest
from summarize_log import summarize


class SummaryTests(unittest.TestCase):
    def test_empty_never_passes_or_reports_zero_latency(self):
        result = summarize([])
        self.assertIsNone(result["seekCompletionOnly"]["p95Ms"])
        self.assertIsNone(result["sampledPeakPhysicalFootprintBytes"])
        self.assertIn("NOT MEASURED", result["seekToDisplayedFrame"])
        self.assertIn("NO AUTOMATIC PASS", result["verdict"])

    def test_completion_not_display_and_failed_seeks_excluded(self):
        rows = [{"event": "seekCompletion", "latencyMilliseconds": value, "completed": True}
                for value in range(1, 101)]
        rows.append({"event": "seekCompletion", "latencyMilliseconds": 999, "completed": False})
        result = summarize(rows)
        self.assertEqual(result["seekCompletionOnly"]["count"], 100)
        self.assertEqual(result["seekCompletionOnly"]["p95Ms"], 95)
        self.assertIn("NOT MEASURED", result["droppedDisplayedFrames"])

    def test_samples_and_export_failures_preserved(self):
        result = summarize([
            {"event": "resourceSample", "physicalFootprintBytes": 100, "thermalState": 0},
            {"event": "resourceSample", "physicalFootprintBytes": 200, "thermalState": 2},
            {"event": "exportEnded", "state": "failed", "wallSeconds": 10},
        ])
        self.assertEqual(result["sampledPeakPhysicalFootprintBytes"], 200)
        self.assertEqual(result["thermalStatesObserved"], [0, 2])
        self.assertEqual(result["exportOutcomes"][0]["state"], "failed")


if __name__ == "__main__":
    unittest.main()
