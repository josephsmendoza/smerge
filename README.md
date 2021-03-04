## Smart Merge
This is a utility to help resolve folder merges.
```
usage: smerge (-d destination | -c config.json) [source]
-n        --name package name
-c      --config json config file
-s        --skip file glob to skip, can be used multiple times.
-d --destination absolute path to destination
-N       --named named destination subfolder, can be used multiple times.
-F    --fallback fallback destination subdirectory
-A      --anchor single anchor, can be used multiple times
-a    --absolute use absolute paths in package map
-h        --help This help information.
a named folder contains only folders which share the same structure with eachother.
if no source is provided, the config will be output.
otherwise, a smart merge map will be generated and output.
```