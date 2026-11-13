--!strict

----------------------------------------------------------------------
-- WordKits
----------------------------------------------------------------------
-- The curated word list behind a `WordKit` spawn volume (Phase 8 stage 7,
-- wiki/design/boss-arena.md § Word kits), and the shuffle that turns a word
-- into the letters laid out in the world.
--
-- Why a list and not "any dictionary word": the Dictionary holds about 80k
-- words, obscure and geographic ones included, and an anagram nobody can
-- find is not a reward. These are common words a school-age player knows,
-- with no proper nouns and nothing violent, adult or frightening.
--
-- Why these words in particular: the kit is one colour, so the whole word's
-- energy lands in one reservoir, and the design intent is that it pays for
-- roughly one top-tier (T3) cast. Words made only of the commonest letters
-- (TRAIN, STONE) are worth 7-10 energy, which would be a poor reward, so the
-- lists lean on words with a mix of letters (Q, J, K, Y, W, H, B, C, M, P).
-- Every word is worth between 15 and 30 energy; the `wordkit_words_valid`
-- suite asserts the band, so adding a word that falls outside it fails a test
-- instead of quietly changing the reward.
--
-- Adding a word: uppercase A-Z, the right length, in the Dictionary (the
-- suite checks all three), no palindromes (a palindrome has no order that
-- reads differently from either side).
----------------------------------------------------------------------

local WORDS_BY_LENGTH_SOURCE: { [number]: string } = {
	[5] = [[
BEACH BLOCK BLUSH BRAVE BRUSH BUDDY BUNNY CANDY CHAIR CHALK CHEEK CHESS CLIMB
CLOCK COMIC CYCLE FAIRY FLAME FUNNY HABIT HAPPY HIPPO HOBBY HONEY JELLY JOKER
JOLLY JUICE JUMBO LUCKY LUNCH MAGIC MAJOR MOVIE PARTY PEACH PIXEL PRIZE PUNCH
PUPPY QUEEN QUICK QUIET QUILT QUOTE SHAPE SHARK SHEEP SHELF SPEAK SPICY SQUAD
SQUID STICK SYRUP TEACH THUMB TRICK TRUCK VOICE WATCH WHALE WHEAT WHEEL WHISK
YACHT YOUTH YUMMY ZEBRA
]],
	[6] = [[
BASKET BOUNCE BREEZE BRIDGE BUBBLE BUCKET CACTUS CAMERA CARPET CHEESE CHERRY
CIRCLE CLOVER COBWEB COOKIE CRAYON DONKEY FABRIC FAMILY FIDDLE FINGER FLAVOR
FLIGHT FLOWER FRIEND FROZEN HAMMER HELMET HOCKEY HUNGRY JACKET JERSEY JOYFUL
JUMBLE JUNGLE KETTLE KITTEN LAUNCH LIZARD MARBLE MARKET MONKEY MOTHER MUFFIN
MUSCLE NAPKIN NUMBER OXYGEN PAJAMA PEBBLE PENCIL PEPPER PICNIC PLAYER PLENTY
POCKET PUPPET PURPLE RABBIT ROCKET SCHOOL SHADOW SHOVEL SHRIMP SOCCER SPEECH
SUMMER SYMBOL TICKET TROPHY TURKEY WAFFLE WINDOW WIZARD YELLOW ZIPPER
]],
}

-- A reshuffle that happens to read as the word (or its mirror image, which a
-- player standing on the other side of the row sees) is thrown away and
-- redone, up to this many times. A word has at least 20 distinct orderings,
-- so the chance of exhausting this is vanishingly small.
local MAX_SHUFFLE_ATTEMPTS = 20

local wordsByLength: { [number]: { string } } = {}
local lengths: { number } = {}
for length, source in WORDS_BY_LENGTH_SOURCE do
	local words: { string } = {}
	for word in string.gmatch(source, "%S+") do
		table.insert(words, word)
	end
	wordsByLength[length] = words
	table.insert(lengths, length)
end
table.sort(lengths)

local WordKits = {}

-- The word lengths a kit can be, ascending.
function WordKits.lengths(): { number }
	return table.clone(lengths)
end

function WordKits.isSupportedLength(length: number): boolean
	return wordsByLength[length] ~= nil
end

-- The supported length closest to `length` (the lower one on a tie).
function WordKits.nearestLength(length: number): number
	local best = lengths[1]
	for _, candidate in ipairs(lengths) do
		if math.abs(candidate - length) < math.abs(best - length) then
			best = candidate
		end
	end
	return best
end

-- The curated words of one length, uppercase, or an empty list for an
-- unsupported length. A copy: callers cannot damage the list.
function WordKits.words(length: number): { string }
	local words = wordsByLength[length]
	if words == nil then
		return {}
	end
	return table.clone(words)
end

-- A random word of `length`, avoiding `avoid` when there is any other choice
-- so a re-roll never hands back the kit that was just there.
function WordKits.pick(length: number, avoid: string?): string
	local words = wordsByLength[length] or wordsByLength[WordKits.nearestLength(length)]
	local choice = words[math.random(1, #words)]
	while avoid ~= nil and choice == avoid and #words > 1 do
		choice = words[math.random(1, #words)]
	end
	return choice
end

-- The word's letters in a random order that does not read as the word from
-- either end of the row.
function WordKits.shuffledLetters(word: string): { string }
	local letters: { string } = {}
	for i = 1, #word do
		table.insert(letters, string.sub(word, i, i))
	end
	local mirrored = string.reverse(word)

	for _ = 1, MAX_SHUFFLE_ATTEMPTS do
		for i = #letters, 1, -1 do
			local j = math.random(1, i)
			letters[i], letters[j] = letters[j], letters[i]
		end
		local arranged = table.concat(letters)
		if arranged ~= word and arranged ~= mirrored then
			break
		end
	end
	return letters
end

return WordKits
