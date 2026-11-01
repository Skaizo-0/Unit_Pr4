using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class CpuProjectBuilder
{
    [MenuItem("Lesson 4/Create Scene and Build Development Player")]
    public static void Build()
    {
        Directory.CreateDirectory("Assets/Scenes");
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var camera = new GameObject("Main Camera").AddComponent<Camera>();
        camera.backgroundColor = new Color(0.035f, 0.08f, 0.11f);
        camera.clearFlags = CameraClearFlags.SolidColor;
        var controller = new GameObject("CPU Lookup Lesson");
        controller.AddComponent<LookupExercise>();
        controller.AddComponent<LookupBenchmark>();
        EditorSceneManager.SaveScene(scene, "Assets/Scenes/CpuLab.unity");
        string[] scenes = { "Assets/Scenes/CpuLab.unity" };
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(scenes[0], true) };
        PlayerSettings.companyName = "Mire Education";
        PlayerSettings.productName = "Unity CPU Lab";
        PlayerSettings.defaultScreenWidth = 1100;
        PlayerSettings.defaultScreenHeight = 700;
        PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
        PlayerSettings.runInBackground = true;
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, ScriptingImplementation.Mono2x);
        PlayerSettings.gcIncremental = true;
        QualitySettings.vSyncCount = 0;
        AssetDatabase.SaveAssets();
        Directory.CreateDirectory("Build");
        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = scenes,
            locationPathName = Path.GetFullPath("Build/UnityCpuLab.exe"),
            target = BuildTarget.StandaloneWindows64,
            options = BuildOptions.Development
        });
        if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
            throw new BuildFailedException(report.summary.result.ToString());
        Debug.Log($"LESSON4 BUILD PASS bytes={report.summary.totalSize}");
    }
}
