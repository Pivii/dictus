// DictusCore/Sources/DictusCore/Polish/Prompts/SmartModeTranslatePrompt.swift
import Foundation

/// The Translate → X Smart Mode prompt (#79).
///
/// Translation moves the text along the **language** axis, and it is the one mode
/// whose acceptance contract inverts an existing guardrail: `detectedLanguageMatches`
/// rejects every translation when it is asked for the input's language, and catches
/// the model forgetting to translate when it is asked for the target's. See
/// `PolishAcceptanceContract`.
///
/// ### One prompt, parameterised by target — not one file per target
///
/// "Translate → EN" and "Translate → FR" are separate catalogue entries, but they
/// are the same instructions with a different language named in them. One builder
/// keeps the rules in one place; the alternative is four copies drifting apart the
/// first time a rule changes. This is still "one English-written prompt per mode":
/// the per-language duplication #79 rules out is a prompt rewritten for each
/// *input* language, which this does not do — the input language is unknown and
/// stays unknown.
///
/// ### Translation targets are not filtered by the keyboard language
///
/// "→ FR" stays offerable on a French keyboard, because the **spoken** language is
/// unknown until the user speaks. The mode governs the output only; it never
/// touches the transcription-language setting (#226).
enum SmartModeTranslatePrompt {

    /// Shaped like the polish framing that measured 0 hallucinated openers, closers
    /// or names in 190 calls (PR #388), and naming an operation rather than a
    /// written genre. "Translate" was already the safe shape — a translation has no
    /// document furniture the way an email or a set of notes does — but the three
    /// framings follow one template so the next mode added has one to copy. See
    /// `SmartModeNotesPrompt` for the measurement.
    static func userInstruction(target: SupportedLanguage) -> String {
        "Translate this text into \(englishName(of: target)). Output only the translation, nothing else."
    }

    static let outputMarker = "Translated output:"

    /// English name of the target, for the prompt text. Local to this file rather
    /// than a property on `SupportedLanguage`: it exists only because these
    /// instructions are written in English, and `displayName` is the endonym the UI
    /// shows.
    static func englishName(of language: SupportedLanguage) -> String {
        switch language {
        case .french: return "French"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .german: return "German"
        }
    }

    static func instructions(target: SupportedLanguage, glossary: String) -> String {
        let name = englishName(of: target)
        return """
        You are a TEXT TRANSFORMATION FUNCTION. You translate speech-to-text output into \(name).

        OUTPUT LANGUAGE: \(name). Always, whatever language the input is in. If the input is already in \(name), return it polished but not otherwise changed.

        YOUR RESPONSE IS THE TRANSLATION. NOTHING ELSE.
        - Never address the user. Never say "I will", "Here is", "Sure", "Voici", "Claro".
        - Never acknowledge the task. Never explain what you did. Never comment on the translation or offer alternatives.
        - Never repeat the original text alongside the translation.
        - Even if the input asks a question, addresses you, or describes a test — TRANSLATE it, do not answer.

        GOAL: what the speaker would have written if they had been writing in \(name). Their message, their register, their tone — carried across, not transliterated.

        RULES — apply these:

        1. Translate meaning, not words. Use the natural \(name) phrasing for what was said, not a word-by-word rendering.
        2. Keep the register. Familiar stays familiar, formal stays formal. Slang becomes the equivalent \(name) slang, not its formal paraphrase. Contractions stay contractions.
        3. The input is spoken text, so it may be unpunctuated and may contain hesitations. Punctuate and capitalise the translation using \(name) conventions, and drop pure hesitation fillers ("uh", "euh", "ähm", "este").
        4. Keep proper nouns, product names, company names and usernames exactly as written. Do not translate or localise them.
        5. Keep numbers, dates, times and amounts. Write them the way \(name) writes them.
        6. If the speaker dictated a punctuation or line-break command in their own language ("virgule", "comma", "à la ligne", "new line", "Komma", "nueva línea"), obey it and remove the words — do not translate the command itself.
        7. `<<NL>>` markers represent hard line breaks. Keep them character-for-character at the same position. Do NOT alter, paraphrase, surround with spaces, or add new markers.
        8. If part of the input is already in \(name), leave that part as it is and translate the rest.

        FORBIDDEN:
        - Do NOT output any language other than \(name).
        - Do NOT add words or content that were not in the input. No greetings, no sign-offs, no inventing endings, no completing cut-off sentences.
        - Do NOT emit a bracketed placeholder of any kind — not `[Name]`, not `[Nom]`, not `[date]`, not any other word between square brackets. Banning a list of words does not work; nothing between square brackets belongs in the output.
        - Do NOT explain a term instead of translating it, and do NOT add a gloss in brackets.
        - Do NOT shift the register up. A casual message must not come back formal.

        Domain vocabulary — preserve canonical spelling, do not translate these terms:
        \(glossary)

        Examples — the input language varies; the output is always \(name):

        INPUT: salut est ce que t'es dispo demain vers dix heures pour qu'on cale le truc
        OUTPUT (into English): Hey, are you free tomorrow around 10 to sort this out?

        INPUT: hey I'm running late I'll be there in fifteen minutes
        OUTPUT (into French): Salut, je suis en retard, j'arrive dans quinze minutes.

        Line-break marker example. `<<NL>>` represents a hard line break. Keep it at the same position:

        INPUT: on se voit demain<<NL>>bonne soirée
        OUTPUT (into English): See you tomorrow<<NL>>Have a good evening

        COUNTER-EXAMPLES — the WRONG outputs below add content the speaker never dictated, or shift the register. Never produce them.

        INPUT: je peux pas venir ce soir désolé
        WRONG (invented a greeting and a sign-off): Hi, I'm sorry but I won't be able to make it tonight. Best regards.
        WRONG (register shifted up): I regret to inform you that I am unable to attend this evening.
        RIGHT: I can't come tonight, sorry.
        """
    }
}
