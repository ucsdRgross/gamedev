## Set this script to autoload in your project to cycle between pseudocodes with Z key

extends Node
signal locale_changed

enum PSEUDO_SETTINGS {
	DISABLED,               ## Pseudolocalisation disabled
	replace_with_accents,   ## Replaces all characters in the string with their accented variants
	double_vowels,          ## Doubles all the vowels in the string
	fake_bidi,              ## Fake bidirectional text (simulates right-to-left text)
	override,               ## Replaces all the characters in the string with an asterisk
	skip_placeholders,      ## Skips placeholders for string formatting like %s and %f.
}
var current_pseudo_mode: PSEUDO_SETTINGS = PSEUDO_SETTINGS.DISABLED

func _input(event:InputEvent) -> void:
	if OS.is_debug_build():
		if event.is_pressed():
			match event.as_text():
				"Z":
					cycle_pseudolocalisation()

## changes pseudolocalisation between OFF and various psuedolocalisation styles
func cycle_pseudolocalisation() -> void:
	current_pseudo_mode += 1  # next style
	current_pseudo_mode = current_pseudo_mode % len(PSEUDO_SETTINGS)  # wrap back to 0 using modulo
	locale_changed.emit()  # emit signal so that connected scenes can refresh contents bespokely if needed
	print("Now using PseudoLocalisation mode '%s'" % PSEUDO_SETTINGS.keys()[current_pseudo_mode])
	
	# tailor style
	TranslationServer.pseudolocalization_enabled = current_pseudo_mode != PSEUDO_SETTINGS.DISABLED
	var setting_path: String = "internationalization/pseudolocalization/"
	var i: int = 0
	for setting : String in PSEUDO_SETTINGS.keys():
		i += 1
		ProjectSettings.set_setting(setting_path + setting, current_pseudo_mode == i-1)
	TranslationServer.reload_pseudolocalization()
