extends RefCounted

static func option(key: String,fallback="") -> String:
	var args=OS.get_cmdline_user_args()
	var idx=args.find(key)
	return args[idx+1] if idx>=0 and idx+1<args.size() else fallback

static func examples() -> String:
	var from_arg=option("--examples",OS.get_environment("OPENEXHIBIT_EXAMPLES"))
	if from_arg: return ProjectSettings.globalize_path(from_arg).simplify_path()
	for d in [OS.get_executable_path().get_base_dir().path_join("examples"),ProjectSettings.globalize_path("res://").path_join("../examples").simplify_path(),OS.get_executable_path().get_base_dir().path_join("../examples").simplify_path()]:
		if DirAccess.dir_exists_absolute(d): return d
	return ""

static func first_project() -> String:
	var explicit=option("--project")
	if explicit: return explicit
	var ex=examples()
	return ex.path_join("01-solar/project.oes.json") if ex else ""
