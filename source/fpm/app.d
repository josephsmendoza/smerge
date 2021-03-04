import std.stdio;
import std.getopt;
import std.exception;
import asdf;
import std.range;
import fpm.smerge;
import std.path;
import std.file;

void main(string[] args) {
	Config conf;
	string destination;
	string sourceName;
	string configFile;
	bool absolute;
	//dfmt off
	auto opt=getopt(args, config.passThrough, config.caseSensitive,
		"n|name","package name",&sourceName,
		"c|config","json config file",&configFile,
		"s|skip","file glob to skip, can be used multiple times.",&skip,
		"d|destination","absolute path to destination",&destination,
		"N|named","named destination subfolder, can be used multiple times.",&(conf.nameDirs),
		"F|fallback","fallback destination subdirectory",&(conf.fallback),
		"A|anchor","single anchor, can be used multiple times",&(conf.anchorMap),
		"a|absolute", "use absolute paths in package map", &absolute
	);
	//dfmt on
	if (opt.helpWanted) {
		defaultGetoptPrinter("usage: " ~ args[0] ~ " (-d destination | -c config.json) [source]", opt.options);
		writeln("a named folder contains only folders which share the same structure with eachother.");
		writeln("if no source is provided, the config will be output.");
		writeln("otherwise, a smart merge map will be generated and output");
		return;
	}
	args.popFront();
	if (!configFile.empty) {
		Config aconf=configFile.readText().deserialize!Config();
		if (conf.fallback.empty) {
			conf.fallback = aconf.fallback;
		}
		conf.nameDirs ~= aconf.nameDirs;
		foreach (string anchor, dest; aconf.anchorMap) {
			conf.anchorMap.require(anchor, dest);
		}
	}
	if(conf.anchorMap.empty && !destination.empty){
		conf.anchorMap = generateAnchorMap(destination, conf);
	}
	if(!absolute){
		destination="";
	}
	if (!args.empty) {
		string[string] packageMap=getPackageMap(args[0], conf, sourceName, destination);
		packageMap.serializeToJsonPretty().writeln();
	} else {
		conf.serializeToJsonPretty().writeln();
	}
}
