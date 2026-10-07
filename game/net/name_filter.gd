class_name NameFilter
extends RefCounted

# Blocked anywhere in the name, even glued to other letters.
const ANYWHERE := [
	"fuck", "shit", "bitch", "cunt", "nigger", "nigga", "faggot", "whore", "slut", "pussy", "porn", "twat",
	"asshole", "retard", "hitler",
	"mierda", "pendejo", "culero", "cabron", "maricon", "marica", "chinga", "verga", "malparido", "hijueputa",
	"gonorrea", "mamaguevo", "hijodeputa", "putamadre",
]
# Blocked only as a whole word, because they also hide inside harmless names (Cassandra, Hancock, Ignazio, computadora).
const WHOLE_WORD := [
	"ass", "dick", "cock", "cum", "sex", "fag", "rape", "rapist", "kys", "anal", "tits", "nazi",
	"puta", "puto", "putas", "putos", "culo", "cono", "pene", "polla", "hdp", "ctm", "ptm", "csm", "mrd", "pija",
]
const LOOKALIKES := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s", "!": "i"}
const ACCENTS := {"á": "a", "à": "a", "ä": "a", "â": "a", "é": "e", "è": "e", "ë": "e", "ê": "e", "í": "i", "ì": "i",
	"ï": "i", "î": "i", "ó": "o", "ò": "o", "ö": "o", "ô": "o", "ú": "u", "ù": "u", "ü": "u", "û": "u", "ñ": "n", "ç": "c"}

static var _anywhere: Array[RegEx] = []
static var _whole_word: Array[RegEx] = []


static func is_allowed(name: String) -> bool:
	_compile()
	var simplified := _simplify(name)
	var letters_only := RegEx.create_from_string("[^a-z]").sub(simplified, "", true)
	for pattern in _anywhere:
		if pattern.search(letters_only):
			return false
	for word in RegEx.create_from_string("[^a-z]+").sub(simplified, " ", true).split(" ", false):
		for pattern in _whole_word:
			if pattern.search(word):
				return false
	return true


static func _simplify(name: String) -> String:
	var simplified := ""
	var words_split := RegEx.create_from_string("([a-z])([A-Z])").sub(name, "$1 $2", true)
	for character in words_split.to_lower():
		simplified += LOOKALIKES.get(character, ACCENTS.get(character, character))
	return simplified


static func _compile() -> void:
	if not _anywhere.is_empty():
		return
	for word: String in ANYWHERE:
		_anywhere.append(RegEx.create_from_string(_stretchable(word)))
	for word: String in WHOLE_WORD:
		_whole_word.append(RegEx.create_from_string("^%s$" % _stretchable(word)))


# "fuck" also matches "fuuuck": every letter may repeat.
static func _stretchable(word: String) -> String:
	var pattern := ""
	for letter in word:
		pattern += letter + "+"
	return pattern
