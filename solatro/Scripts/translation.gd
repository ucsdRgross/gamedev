extends Object
class_name TRANSLATION

static var revealed : bool = false

static func find(key:StringName) -> String:
	var text : String = TranslationServer.translate(key)
	if revealed:
		var revealed_text : String = TranslationServer.translate(key, 'revealed')
		if revealed_text != key: 
			return revealed_text
	return text
