import haxe.ds.Vector;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;

using StringTools;

/**
 * this map is indexed by the relative path of a matching file in a package directory.
 * the vector contains 3 entries, which are (in order): source path, dest path, identifier.
 * SMerge has constants to make accessing these values more readable,
 * with comments documenting what they are.
 */
typedef PackageMap = Map<String, Vector<String>>;

class SMerge {
	/**
	 * List of files/folders to skip when building mappings.
	 * When building an anchor map, this list is also used to skip identifiers.
	 */
	var skip = new Array<String>();

	/**
	 * When building a package map,
	 * if no matches were found,
	 * map the content root to this sub-directory of the destination.
	 */
	var fallback:String=null;

	/**
	 * List of subdirectories in the destination
	 * which only contain folders named after the packages they contain.
	 */
	var nameDirs = new Array<String>();

	/**
	 * Map of anchors.
	 * An anchor is a key/value pair where the key is identifying information about a file,
	 * and the value is the subdirectory of the destination that the matching file belongs in.
	 */
	var anchorMap = new Map<String,String>();

	/**
	 * the name used for directories named after the package they contain
	 */
	public static final NAMEDIR = "NAMEDIR";

	/**
	 * the folder in the package dir to copy files from
	 */
	public static final SOURCE_PATH=0;
	/**
	 * the folder in the destination to copy files to
	 */
	public static final DEST_PATH=1;
	/**
	 * the identifier from the anchor that matched
	 */
	public static final IDENTIFIER=2;

	/**
	 * Check if path matches any of the globs
	 * @param path a path string
	 * @param globs an array of glob strings
	 * @return Bool true if any globs matched, false otherwise.
	 */
	private function globsMatch(path:String, globs:Array<String>):String {
		for (glob in globs) {
			if (globMatch(path,glob)) {
				return glob;
			}
		}
		return null;
	}

	private function globMatch(path:String, glob:String){
		return hx.files.GlobPatterns.toEReg(glob).match(path);
	}

	function buildAnchorMap(destination:String) {
		/**
		 * this function needs a copy of skip because
		 * entries will be added that shouldn't outlive
		 * the function call.
		 */
		var skip = this.skip.concat(["*."]);

		/**
		 * destination must be normalized
		 * to prevent string manipulation bugs.
		 */
		destination = Path.normalize(destination);

		/**
		 * I prefer queues to recursion because
		 * when traversing a file tree, the amount
		 * of recursion can quickly consume memory
		 */
		var queue = [destination];

		/**
		 * a new anchor map is returned instead of adding to this.anchorMap
		 * to allow the map to be modified if needed before being used.
		 */
		var anchorMap = new Map<String,String>();

		while (queue.length != 0) {
			/**
			 * this variable shouldn't be modified by the following loop
			 * because it is needed as is for every loop iteration
			 */
			final dirname = queue.pop();

			for (basename in FileSystem.readDirectory(dirname)) {
				/**
				 * don't process files which match globs in skip[]
				 */
				if (globsMatch(basename, skip) != null) {
					continue;
				}

				/**
				 * if this is a directory, queue it for the outer loop
				 */
				var isDir = false;

				var path = Path.join([dirname, basename]);
				if (FileSystem.isDirectory(path)) {
					queue.push(path);
					isDir = true;
				}

				/**
				 * use the path extension by default,
				 * with the basename as a fallback.
				 */
				var isBasename = false;

				var identifier = "*." + Path.extension(basename);
				if (skip.contains(identifier)) {
					identifier = basename;
					isBasename = true;
				}

				/**
				 * anchor map keys must be paths relative to the destination.
				 */
				var destPath = dirname.substring(destination.length + 1);

				if (destPath == "") {
					destPath = ".";
				}
				for (nameDir in nameDirs) {
					/**
					 * don't add basename globs for named directories
					 */
					if (destPath == nameDir) {
						if (isDir && isBasename) {
							identifier = "*.";
						}
					} else {
						/**
						 * remove the named segment from entries further down.
						 */
						if (destPath.startsWith(nameDir)) {
							destPath = destPath.substring(nameDir.length + 1);
							var destPathSegments = destPath.split("/");
							destPathSegments.shift();
							destPathSegments.unshift(NAMEDIR);
							destPathSegments.unshift(nameDir);
							destPath = Path.join(destPathSegments);
						}
					}
				}
				/**
				 * if this identifier has matched elsewhere, then it's not unique.
				 */
				for (anIdentifier => aDestPath in anchorMap) {
					if (anIdentifier == identifier) {
						if (aDestPath != destPath) {
							anchorMap.remove(anIdentifier);
							skip.push(identifier);
						} else {
							identifier="*.";
						}
						break;
					}
				}
				if (!skip.contains(identifier)) {
					anchorMap[identifier]=destPath;
				}
			}
		}
		return anchorMap;
	}

	/**
	 * use this.anchorMap to build a package map of packageDir
	 * @param packageDir a folder containing files to be added
	 */
	public function buildPackageMap(packageDir:String, packageName:String=null) {
		/**
		 * paths must be normalized to prevent string manipulation bugs
		 */
		packageDir = Path.normalize(packageDir);
		/**
		 * use a queue instead of recursion
		 */
		var queue = [packageDir];
		/**
		 * this is the returned data
		 */
		var packageMap = new PackageMap();
		/**
		 * a package name is generated in case a named directory is matched
		 */
		if(packageName==null){
			packageName=Path.withoutDirectory(packageDir);
		}

		while (queue.length != 0) {
			/**
			 * this shouldn't be modified in the loop
			 */
			final dirname = queue.pop();
			for (basename in FileSystem.readDirectory(dirname)) {
				/**
				 * skip any basenames in the skip array
				 */
				if (globsMatch(basename, skip) != null) {
					continue;
				}
				/**
				 * add any directories to the queue
				 */
				final path = Path.join([dirname, basename]);
				if (FileSystem.isDirectory(path)) {
					queue.push(path);
				}
				/**
				 * add the relative path of any matching basenames
				 * to the package map including the matched info
				 */
				var sourcePath = path.substring(packageDir.length + 1);
				for (anIdentifier => destPath in anchorMap) {
					if(globMatch(basename,anIdentifier)){
						var entry=new Vector(3);
						entry[0]=Path.directory(sourcePath);
						entry[1]=destPath.replace(NAMEDIR,packageName);
						entry[2]=anIdentifier;
						packageMap[sourcePath]=entry;
					}
				}
			}
		}

		return packageMap;
	}

	public function new() {} // why do i need this

	static function main() { // test method
		var smerge = new SMerge();
		smerge.anchorMap = smerge.buildAnchorMap("/media/hdd/Games/SteamLibrary/steamapps/common/Skyrim");
		trace(smerge.anchorMap);
		trace(smerge.buildPackageMap("/media/ssd/skse"));
	}
}
