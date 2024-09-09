package;

import lime.tools.HashlinkHelper;
import hxp.Haxelib;
import hxp.HXML;
import hxp.Path;
import hxp.Log;
import hxp.NDLL;
import hxp.System;
import lime.tools.Architecture;
import lime.tools.AssetHelper;
import lime.tools.AssetType;
import lime.tools.CPPHelper;
import lime.tools.DeploymentHelper;
import lime.tools.HXProject;
import lime.tools.JavaHelper;
import lime.tools.NekoHelper;
import lime.tools.NodeJSHelper;
import lime.tools.Orientation;
import lime.tools.Platform;
import lime.tools.PlatformTarget;
import lime.tools.ProjectHelper;
import sys.io.File;
import sys.io.Process;
import sys.FileSystem;

class SwitchPlatform extends PlatformTarget {
	private var executablePath:String;
	private var applicationDirectory:String;

	public function new(command:String, _project:HXProject, targetFlags:Map<String, String>) {
		super(command, _project, targetFlags);

		var defaults = new HXProject();

		defaults.meta = {
			title: "MyApplication",
			description: "",
			packageName: "com.example.myapp",
			version: "1.0.0",
			company: "",
			companyUrl: "",
			buildNumber: null,
			companyId: ""
		};

		defaults.app = {
			main: "Main",
			file: "MyApplication",
			path: "bin",
			preloader: "",
			swfVersion: 17,
			url: "",
			init: null
		};

		defaults.window = {
			width: 1280,
			height: 720,
			parameters: "{}",
			background: 0xFFFFFF,
			fps: 30,
			hardware: true,
			display: 0,
			resizable: true,
			borderless: false,
			orientation: Orientation.AUTO,
			vsync: false,
			fullscreen: false,
			allowHighDPI: true,
			alwaysOnTop: false,
			antialiasing: 0,
			allowShaders: true,
			requireShaders: false,
			depthBuffer: true,
			stencilBuffer: true,
			colorDepth: 32,
			maximized: false,
			minimized: false,
			hidden: false,
			title: ""
		};

		defaults.architectures = [Architecture.X64];
		defaults.window.width = 0;
		defaults.window.height = 0;
		defaults.window.fullscreen = true;
		defaults.window.requireShaders = true;

		for (i in 1...project.windows.length)
		{
			defaults.windows.push(defaults.window);
		}

		defaults.window.allowHighDPI = false;

		defaults.merge(project);
		project = defaults;

		for (excludeArchitecture in project.excludeArchitectures) {
			project.architectures.remove(excludeArchitecture);
		}

		targetDirectory = Path.combine(project.app.path, "switch");
		applicationDirectory = targetDirectory + '/bin/';
		executablePath = applicationDirectory + project.app.file + '.nro';
	}

	public override function build():Void {
		// use devkitpro to build the project
		var devkitpro = System.findDevkitPro(); // Returns a map with path, toolsPath, and switchPath
		var devkitproPath = devkitpro[0];
		var devkitproToolsPath = devkitpro[1];
		var devkitproSwitchPath = devkitpro[2];

		// Build the project to cpp with devkitpro
		var hxml = targetDirectory + "/haxe/" + buildType + ".hxml";

		System.mkdir(targetDirectory);

		var haxeArgs = [hxml];
		var flags = [];

		haxeArgs.push("-D");
		haxeArgs.push("HXCPP_M64");
		flags.push("-DHXCPP_M64");

		var nacptoolArgs = [
			"--create",
			project.meta.title,
			project.meta.company,
			project.meta.version,
			targetDirectory + "/romfs/control.nacp",
			"--titleid=0x0100" + project.meta.companyId + project.meta.title
		];

		System.mkdir(targetDirectory + "/romfs");

		// create nacp info
		System.runCommand("", "nacptool", nacptoolArgs);

		// COMPILE CPP FILES
		System.runCommand("", "haxe", haxeArgs);

		CPPHelper.compile(project, targetDirectory + "/obj", flags);

		// CREATE .ELF
		var elfArgs = [
			"-o",
			targetDirectory + "/bin/" + project.app.file + ".elf",
			targetDirectory + "/obj/ApplicationMain.cpp.o",
			"-L" + devkitproSwitchPath + "/lib"
		];

		System.runCommand("", "gcc", elfArgs);

		// COMPILE NRO
		var nroArgs = [
			"-o",
			executablePath,
			"-n",
			project.meta.title,
			"-a",
			targetDirectory + "/romfs",
			targetDirectory + "/obj/ApplicationMain.cpp.o"
		];

		System.runCommand("", "elf2nro", nroArgs);
	}

	public override function clean():Void
	{
		if (FileSystem.exists(targetDirectory))
		{
			System.removeDirectory(targetDirectory);
		}
	}

	public override function deploy():Void
	{
		if (targetFlags.exists("gdrive") || targetFlags.exists("zip"))
		{
			DeploymentHelper.deploy(project, targetFlags, targetDirectory, "Switch");
		}
		else
		{
			var rootDirectory = targetDirectory + "/bin";
			var paths = System.readDirectory(rootDirectory, [project.app.file + ".nro"]);
			var files = [];

			for (path in paths)
			{
				files.push(path.substr(rootDirectory.length + 1));
			}

			var name = project.meta.title + " (" + project.meta.version + " build " + project.meta.buildNumber + ")";
			name += " (Switch).nro";

			var outputPath = "dist/" + name;

			System.mkdir(targetDirectory + "/dist");

			System.copyFile(executablePath, Path.combine(targetDirectory, outputPath));
		}
	}

	public override function display():Void {
		Sys.println(executablePath);
	}

	public override function update():Void {
		AssetHelper.processLibraries(project, targetDirectory);

		if (project.targetFlags.exists("xml"))
		{
			project.haxeflags.push("-xml " + targetDirectory + "/types.xml");
		}

		for (asset in project.assets)
		{
			if (asset.embed && asset.sourcePath == "")
			{
				var path = Path.combine(targetDirectory + "/obj/tmp", asset.targetPath);
				System.mkdir(Path.directory(path));
				AssetHelper.copyAsset(asset, path);
				asset.sourcePath = path;
			}
		}

		System.mkdir(targetDirectory);
		System.mkdir(targetDirectory + "/obj");
		System.mkdir(targetDirectory + "/haxe");
		System.mkdir(applicationDirectory);

		var context = generateContext();
		context.OUTPUT_DIR = targetDirectory;

		ProjectHelper.recursiveSmartCopyTemplate(project, "haxe", targetDirectory + "/haxe", context);
		ProjectHelper.recursiveSmartCopyTemplate(project, "cpp/hxml", targetDirectory + "/haxe", context);

		ProjectHelper.recursiveSmartCopyTemplate(project, "cpp/static", targetDirectory + "/obj", context);
	}

	private function generateContext():Dynamic {
		var context = project.templateContext;

		context.HL_FILE = targetDirectory + "/obj/ApplicationMain" + (project.defines.exists("hlc") ? ".c" : ".hl");
		context.CPPIA_FILE = targetDirectory + "/obj/ApplicationMain.cppia";
		context.CPP_DIR = targetDirectory + "/obj";
		context.BUILD_DIR = project.app.path + "/switch";

		return context;
	}
}