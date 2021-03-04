module fpm.smerge;

import std.file;
import std.digest;
import std.array;
import std.path;
import std.algorithm;

private bool globsMatch(string path, string[] patterns) {
	foreach (string pattern; patterns) {
		if (path.globMatch!(CaseSensitive.no)(pattern)) {
			return true;
		}
	}
	return false;
}

private string hexRead(string path, ulong length) {
	return toHexString(cast(ubyte[]) path.read(4));
}

private string getContentRoot(string root) {
	auto current = root;
	while (true) {
		auto dirEntries = dirEntries(current, SpanMode.shallow).array;
		if (dirEntries.length == 1) {
			if (dirEntries[0].isDir) {
				current = dirEntries[0].name;
				continue;
			}
		}
		break;
	}
	return current.relativePath(root);
}

class SMerge {

	/// list of file/folder names and identifiers to skip
	string[] skip;
	/// when no anchors match, map the content root to this path
	string fallback;
	/// the segment immediatley following one of these paths is a unique name
	string[] nameDirs;
	/// a map of anchors to their corresponding directories
	string[string] anchorMap;

	/// generate an anchor map from a destination
	string[string] generateAnchorMap(string baseDir) {
		import std.algorithm.mutation : remove;

		/// this function needs to use a copy of skip[] since put() 
		/// will add entries which shouldn't outlast the method call
		string[] skip=this.skip~["","glob:*", "head:"];
		string[] queue = [baseDir];
		string[string] map;

		string currentValue() {
			string path = queue[0].relativePath(baseDir);
			foreach (string namedPath; nameDirs) {
				if (path.startsWith(namedPath)) {
					if (path.length == namedPath.length) {
						/// don't match anything in a named directory,
						/// it won't stay here in the package map
						// TODO: fix this
						return null;
					}
					/// remove the named segment from the path
					path = path.pathSplitter().array.remove(namedPath.pathSplitter()
							.array.length).buildNormalizedPath();
				}
			}
			return path;
		}

		void put(string entry) {

			if (currentValue == null || skip.canFind(entry)) {
				return;
			}

			if (map.keys.canFind(entry)) {
				if (map[entry] != currentValue) {
					map.remove(entry);
					skip ~= entry;
				}
			} else {
				map[entry] = currentValue;
			}
		}

		while (queue.length != 0) {
			foreach (string entry; queue[0].dirEntries(SpanMode.shallow)) {
				if (entry.baseName.globsMatch(skip)) {
					continue;
				}
				if (entry.isDir()) {
					put("glob:" ~ entry.baseName);
					queue ~= entry;
				} else {
					put("glob:*" ~ entry.extension);
					put("head:" ~ entry.hexRead(4));
				}
			}
			queue.popFront();
		}

		return map;
	}

	/// generate a package map from a config
	public string[string] getPackageMap(string packageDir, string packageName = "", string destDir = "") {
		string[string] map;
		if (packageName.empty) {
			packageName = packageDir.baseName;
		}

		foreach (string entry; packageDir.dirEntries(SpanMode.depth)) { //for each file node in the package dir
			foreach (string anchor, dest; anchorMap) { //for each anchor
				if (anchor.startsWith("glob:")) { //for glob anchors
					anchor = anchor["glob:".length .. $]; //strip the glob identifier
					if (entry.baseName.globMatch!(CaseSensitive.no)(anchor)) { //if the file node matches
						map[entry.dirName.relativePath(packageDir)] = dest; //map the parent folder to the destination
					}
				}
				if (anchor.startsWith("header:")) { //for header anchors
					anchor = anchor["header:".length .. $]; //strip the header identifier
					if (anchor == entry.hexRead(anchor.length / 2)) { //if the header matches
						map[entry.dirName.relativePath(packageDir)] = dest; //map parent to destination
					}
				}
			}
		}

		foreach (string keya; map.keys) { //compare every key
			foreach (string keyb; map.keys) { //to every other key
				if (keya == keyb) { //except itself
					continue;
				}
				if (keyb.startsWith(keya)) { //if one key is parent to the other
					string vala = map[keya];
					string valb = map[keyb];
					if (valb.startsWith(vala)) { //and the coresponding value is parent to the other
						immutable subKey = keyb[keya.length .. $];
						immutable subVal = valb[vala.length .. $];
						if (subKey == subVal) { //and the children match
							map.remove(keyb); // remove the duplicate
						}
					}
				}
			}
		}

		foreach (string source, dest; map) {
			foreach (string namedDir; nameDirs) { //for each named directory
				if (dest.startsWith(namedDir)) { //if the anchor destination is in a named directory
					map[source] = namedDir.buildPath(packageName, dest[namedDir.length .. $]); // insert the named segment
				}
			}
		}

		string contentRoot = packageDir.getContentRoot();

		if (map.empty && !fallback.empty) {
			map[contentRoot] = fallback;
		}

		foreach (string source, dest; map) {
			if (source.length >= contentRoot.length) {
				// if the source path is not longer than, 
				// and therefore not a sub-directory of,
				// the content root, we don't need to modify it.
				continue;
			}
			map.remove(source);
			/// at most, move up to the content root.
			ulong minSegmentsCount = contentRoot.pathSplitter.array.length;
			string[] destSegments = dest.pathSplitter.array;
			immutable ulong destSegmentsCount = destSegments.length;
			/// at most, move up to the destination root.
			if (destSegmentsCount < minSegmentsCount) {
				minSegmentsCount = destSegmentsCount;
			}
			dest = destSegments[0 .. minSegmentsCount - 1].buildPath;
			string[] sourceSegments = source.pathSplitter.array;
			source = sourceSegments[0 .. minSegmentsCount - 1].buildPath;
			map[source] = dest;
		}

		map.remove(""); // remove any empty entry that might have snuck in

		if (!destDir.empty) {
			string[string] absmap;
			foreach (string source, dest; map) {
				absmap[packageDir.buildNormalizedPath(source)] = destDir.buildNormalizedPath(dest);
			}
			map = absmap;
		}

		return map;
	}
}
