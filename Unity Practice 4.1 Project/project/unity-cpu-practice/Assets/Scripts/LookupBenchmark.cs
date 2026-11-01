using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using Unity.Profiling;
using UnityEngine;
using UnityEngine.Profiling;

[RequireComponent(typeof(LookupExercise))]
public sealed class LookupBenchmark : MonoBehaviour
{
    public const int WarmupFrames = 300;
    public const int MeasurementFrames = 300;
    public const int ExpectedChecksum = 6168064;
    private static readonly ProfilerMarker BatchMarker = new ProfilerMarker("Lesson4.LookupBatch");
    private readonly int[] queries = new int[1024];
    private readonly int[] results = new int[1024];
    private readonly long[] ticks = new long[MeasurementFrames];
    private readonly int[] checksums = new int[MeasurementFrames];
    private readonly bool[] validity = new bool[MeasurementFrames];
    private LookupExercise exercise;
    private int frames;
    private int checksum;
    private bool valid;
    private bool allValid = true;
    private bool quitAfterMeasure;
    private bool binaryProfile;
    private string outputDirectory;
    private string csvPath;
    private string summary = "Capture pending";
    private GUIStyle textStyle;

    private void Start()
    {
        exercise = GetComponent<LookupExercise>();
        QualitySettings.vSyncCount = 0;
        Application.targetFrameRate = -1;
        Application.runInBackground = true;
        outputDirectory = Application.persistentDataPath;
        string[] arguments = Environment.GetCommandLineArgs();
        for (int argument = 1; argument < arguments.Length; argument++)
        {
            switch (arguments[argument])
            {
                case "--output-dir":
                    if (++argument >= arguments.Length)
                        throw new ArgumentException("--output-dir requires a directory");
                    outputDirectory = Path.GetFullPath(arguments[argument]);
                    break;
                case "--quit-after-measure":
                    quitAfterMeasure = true;
                    break;
                case "--cpu-profile":
                    if (++argument >= arguments.Length)
                        throw new ArgumentException("--cpu-profile requires a .raw path");
                    string profilePath = Path.GetFullPath(arguments[argument]);
                    Directory.CreateDirectory(Path.GetDirectoryName(profilePath));
                    Profiler.logFile = profilePath;
                    Profiler.enableBinaryLog = true;
                    Profiler.enabled = true;
                    binaryProfile = true;
                    break;
            }
        }
        Directory.CreateDirectory(outputDirectory);
        csvPath = Path.Combine(outputDirectory, "lookup.csv");
        int independentChecksum = 0;
        for (int query = 0; query < queries.Length; query++)
        {
            queries[query] = (query * 37) % 4096;
            independentChecksum += queries[query] * 3 + 7;
        }
        if (independentChecksum != ExpectedChecksum)
            throw new InvalidOperationException("Reference checksum does not match generated queries");
        UnityEngine.Debug.Log("LOOKUP OUTPUT " + csvPath);
    }

    private void Update()
    {
        long elapsed;
        using (BatchMarker.Auto())
        {
            long started = Stopwatch.GetTimestamp();
            checksum = exercise.ExecuteBatch(queries, results);
            elapsed = Stopwatch.GetTimestamp() - started;
        }
        valid = checksum == ExpectedChecksum;
        for (int query = 0; query < queries.Length; query++)
            valid &= results[query] == ((query * 37) % 4096) * 3 + 7;
        allValid &= valid;
        if (frames < WarmupFrames + MeasurementFrames)
        {
            if (frames >= WarmupFrames)
            {
                int sample = frames - WarmupFrames;
                ticks[sample] = elapsed;
                checksums[sample] = checksum;
                validity[sample] = valid;
            }
            frames++;
            if (frames == WarmupFrames + MeasurementFrames)
                Export();
        }
    }

    private void Export()
    {
        if (binaryProfile)
        {
            Profiler.enabled = false;
            Profiler.enableBinaryLog = false;
        }
        var csv = new StringBuilder("frame,elapsed_ms,checksum,queries,valid\n");
        for (int sample = 0; sample < MeasurementFrames; sample++)
        {
            double milliseconds = ticks[sample] * 1000.0 / Stopwatch.Frequency;
            csv.Append(sample + 1).Append(',')
                .Append(milliseconds.ToString("F9", CultureInfo.InvariantCulture)).Append(',')
                .Append(checksums[sample]).Append(",1024,")
                .Append(validity[sample] ? "true" : "false").Append('\n');
        }
        File.WriteAllText(csvPath, csv.ToString(), new UTF8Encoding(false));
        long[] ordered = (long[])ticks.Clone();
        Array.Sort(ordered);
        double median = (ordered[149] + ordered[150]) * 500.0 / Stopwatch.Frequency;
        summary = "300 samples complete | median " + median.ToString("F6", CultureInfo.InvariantCulture)
            + " ms | all valid: " + allValid;
        UnityEngine.Debug.Log("LOOKUP COMPLETE " + summary + " | " + csvPath);
        if (quitAfterMeasure)
            Application.Quit(allValid ? 0 : 2);
    }

    private void OnGUI()
    {
        if (textStyle == null)
            textStyle = new GUIStyle(GUI.skin.label) { fontSize = 21, wordWrap = true };
        GUILayout.BeginArea(new Rect(30, 25, Screen.width - 60, Screen.height - 50));
        GUILayout.Label("Unity CPU Lab | Practice 4.1", textStyle);
        GUILayout.Space(20);
        GUILayout.Label("Lesson4.LookupBatch | one batch per Update\n4096 records | 1024 queries", textStyle);
        GUILayout.Label("Warmup: " + Math.Min(frames, WarmupFrames) + "/300 | Measurement: "
            + Math.Max(0, frames - WarmupFrames) + "/300", textStyle);
        GUILayout.Label("Checksum: " + checksum + " (expected 6168064) | valid: " + valid, textStyle);
        GUILayout.Label(summary, textStyle);
        GUILayout.Space(20);
        GUILayout.Label("CSV: " + csvPath, textStyle);
        GUILayout.Label("Edit LookupExercise.cs only. Keep every answer correct.\n"
            + "The batch continues after export for Profiler capture.\n"
            + "Deep Profile OFF | Call Stacks OFF | CPU Usage ON", textStyle);
        GUILayout.EndArea();
    }
}
