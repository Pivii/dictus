# Dictus iOS — App Review History

Purpose: preserve the App Review timeline and exact response wording so it does not have to be reconstructed from Telegram/App Store Connect each time.

Canonical tracking issue: https://github.com/getdictus/dictus-ios/issues/197

Related issues:

- #189 — App Store listing for v1.7.1 screenshots + metadata
- #194 — Guideline 5.1.1(iv): neutral microphone permission wording
- #197 — App Review follow-up history / central thread
- #207 — App Review: Parakeet v3 download progress appears frozen at 4%
- #208 — App Review: no third-party AI data transmission clarification

---

## Timeline

### 2026-06-16 — First build rejection: third-party AI / privacy concern

- App: Dictus: AI Voice Keyboard
- Submission ID: `666c9103-ab91-4852-b683-10e5d3f6840a`
- Review date: June 16, 2026
- Review device: iPad Air 11-inch (M3)
- Version reviewed: `1.7.1 (17)`
- Guidelines: `5.1.1(i)` and `5.1.2(i)`

Apple wrote:

> The app appears to share the user’s personal data with a third-party AI service but the app does not clearly explain what data is sent, identify who the data is sent to, and ask the user’s permission before sharing the data.
>
> Apps may only use, transmit, or share personal data after they meet all of the following requirements:
>
> - Disclose what data will be sent
> - Specify who the data is sent to
> - Obtain the user’s permission before sending data
> - Identify in the privacy policy what data the app collects, how it collects that data, all uses of that data, and confirm any third party the app shares data with provides the same or equal protection

Apple's relevant next step:

> If the app does not send user data to a third-party AI service or does not include a third-party AI service, reply to this rejection to confirm and add this information to the App Review Information section of App Store Connect.

### 2026-06-16 — Pierre's reply to third-party AI / privacy concern

Exact reply sent by Pierre:

> Hello,
>
> Thank you for your review. We would like to clarify a misunderstanding regarding Guidelines 5.1.1(i) and 5.1.2(i).
>
> Dictus does NOT send, transmit, or share any user data with a third-party AI service. There is no third-party AI service involved in the app.
>
> All speech-to-text processing happens 100% on-device:
> - Voice is transcribed locally on the iPhone/iPad using Apple CoreML models (WhisperKit and Parakeet), running entirely offline.
> - No audio, no transcribed text, and no keystrokes ever leave the device.
> - The app makes NO network requests to OpenAI, Anthropic, Google, or any other AI/LLM provider.
> - The only network activity in the entire app is a one-time download of the on-device speech model files from Hugging Face. These model files run locally afterward; no user content is ever uploaded.
>
> Data collection:
> - The app collects no data. There are no analytics, no tracking, and no third-party data-collection SDKs.
> - Our App Store privacy nutrition label is "Data Not Collected".
> - The "Full Access" permission for the keyboard extension is requested solely to enable microphone access from within the keyboard, which iOS otherwise blocks. We do not use it for network access, clipboard reading, or keystroke logging.
> The word "AI" in the app name refers to the on-device machine-learning speech recognition (CoreML neural models), not to any cloud or third-party AI service.
>
> Our privacy policy already reflects this and confirms no data is shared with any third party:
> https://www.getdictus.com/en/privacy
>
> We are confident the app fully complies with Guidelines 5.1.1(i) and 5.1.2(i). Please let us know if you need any additional information.
>
> Best regards,
> Pierre

Interpretation: Apple did not continue arguing this third-party AI/privacy point. They moved on to a different privacy issue about microphone permission wording.

### 2026-06-19 — Apple response: microphone permission wording

Apple wrote:

> Hello Pierre,
>
> Thank you for providing this information.
>
> Upon further review, we've identified additional issues that require your attention:
>
> Guideline 5.1.1(iv) - Legal - Privacy - Data Collection and Storage
>
> Issue Description
>
> The app encourages or directs users to allow the app to access the microphone. Specifically, the app directs the user to grant permission in the following way(s):
>
> - A custom message appears before the permission request, and to proceed users press a "Allow microphone" button. Use words like "Continue" or "Next" on the button instead.
>
> Permission requests give users control of their personal information. It is important to respect their decision about how their data is used.
>
> Next Steps
>
> To resolve this issue, please revise the permission request process in the app to not display messages before the permission request with inappropriate words on buttons.
>
> If necessary, you may provide more information about why you are requesting permission before the request appears. If the user is trying to use a feature in the app that won't function without access to the microphone, you may include a notification to inform the user and provide a link to the Settings app.

### 2026-06-19 — Pierre reply: build 18 attached

Pierre wrote:

> We updated the microphone permission button from 'Allow microphone' to 'Continue' per guideline 5.1.1(iv). The new build 1.7.1 (18) is attached.
> Best regards
> Pierre

Tracked in #194.

### 2026-06-24 — Apple response: stale microphone wording + next keyboard button

Apple wrote:

> Hello,
>
> Thank you for your response and information provided. We appreciate your efforts to comply with the App Review Guidelines.
>
> Regarding Guideline 5.1.1, we still found that a custom message appears before the permission request, and to proceed users press a "Allow microphone" button.
>
> To resolve this issue, it would be appropriate to revise the permission request process in the app to not display messages before the permission request with inappropriate words on buttons. You may use words like "Continue" or "Next" on the button instead.
>
> Upon further review, we've identified additional issues that require your attention:
>
> Guideline 4.4.1 - Design - Extensions
>
> Issue Description
>
> Your keyboard extension does not provide a way for users to switch to another keyboard.
>
> Next Steps
>
> Please implement a next keyboard button that enables users to advance to another keyboard.
>
> To ask the system to switch to another keyboard, call the advanceToNextInputMode method of the UIInputViewController class. The system picks the appropriate "next" keyboard; there is no API to obtain a list of enabled keyboards or for picking a particular keyboard to switch to.
>
> The Xcode keyboard template includes the advanceToNextInputMode method as the action of its Next Keyboard button. For best user experience, place your next-keyboard control close to the same screen location as the system keyboard's globe key.
>
> Resources
>
> For more information, please review the App Extension Programming Guide.
>
> Please resubmit the app for review in App Store Connect once any necessary adjustments have been made. We look forward to reviewing your resubmitted app.

Tracked in #197.

### 2026-07-11 — Build 19 prepared/resubmitted

Known from #197 comments:

- 4.4.1 globe fix reworked and merged to main via #204.
- #198 was reverted in #203 after a layout-loop/jetsam regression, root-caused in #202.
- #204 reintroduced the globe fix with layout-loop fix and long-press picker.
- Build bumped to 19 via #206.
- Tag: `v1.7.1-build19`.

### 2026-07-13 — Build 19 rejection: download 4% + repeated privacy concern

- Submission ID: `7e422345-663d-4e05-a13c-911787e4344f`
- Review date: July 13, 2026
- Review device: iPad Air 11-inch (M3)
- OS: iPadOS 26.5.2
- Version reviewed: `1.7.1 (19)`

Apple raised:

1. Guideline `2.1(a)` — app appears frozen when model download starts and stays at 4%.
2. Guideline `5.1.1(iv)` — Apple again believes the app transmits user data to a third-party AI service without sufficient disclosure.

#### Clarification from Pierre about the 4% issue

This is likely not a real freeze. It matches a known Parakeet v3 download progress behavior observed during development/beta:

- Progress appears stuck around 4%.
- Download continues in the background.
- Later the progress jumps close to completion, e.g. ~97%.
- Beta users already perceived this as blocked even though it was still working.

Treat #207 as a Parakeet v3 download progress UX/progress reporting issue, not necessarily a functional download failure.

#### Interpretation of repeated privacy issue

Likely caused by lost review-thread context after build cancellation/resubmission. The earlier privacy clarification was already provided for submission `666c9103-ab91-4852-b683-10e5d3f6840a`, and Apple moved on to other issues afterward.

---

## Recommended reusable reply for current/future repeated privacy rejection

> Hello,
>
> Thank you for your review. We would like to clarify a misunderstanding regarding Guideline 5.1.1(iv).
>
> Dictus does NOT send, transmit, or share any user data with a third-party AI service. There is no cloud or third-party AI service involved in the app's transcription flow.
>
> This clarification was already provided during the first review thread for submission `666c9103-ab91-4852-b683-10e5d3f6840a`; after that clarification, App Review moved on to other issues. Since this build was cancelled and resubmitted, the previous thread context may not be visible to the current reviewer, so we are restating it here.
>
> All speech-to-text processing happens 100% on-device:
> - Voice is transcribed locally on the iPhone/iPad using Apple CoreML models (WhisperKit and Parakeet), running entirely offline.
> - No audio, no transcribed text, and no keystrokes ever leave the device.
> - The app makes no network requests to OpenAI, Anthropic, Google, Apple Intelligence, or any other AI/LLM provider for transcription.
> - The only network activity related to speech recognition is the download of on-device model files. These model files run locally afterward; no user content is ever uploaded as part of this process.
>
> Data collection:
> - The app collects no data. There are no analytics, no tracking, and no third-party data-collection SDKs.
> - Our App Store privacy nutrition label is "Data Not Collected".
> - The "Full Access" permission for the keyboard extension is requested solely to enable microphone access from within the keyboard, which iOS otherwise blocks. We do not use it for clipboard reading, keystroke logging, analytics, tracking, or uploading user content.
>
> The word "AI" in the app name refers to on-device machine-learning speech recognition (CoreML neural models), not to a cloud or third-party AI service.
>
> Our privacy policy reflects this and confirms no data is shared with any third party:
> https://www.getdictus.com/en/privacy
>
> Please let us know if there is a specific screen, wording, or flow that appears to imply third-party AI transmission, and we will correct that wording immediately.
>
> Best regards,
> Pierre

---

## Notes for future agents

- Do not assume Dictus sends data to a third-party AI service. The product position for 1.7.1 is on-device STT only.
- If Apple repeats the third-party AI concern, point to submission `666c9103-ab91-4852-b683-10e5d3f6840a` and reuse the prior wording.
- If Apple mentions the 4% download issue, frame it as Parakeet v3 progress UX/progress reporting; verify, then fix the progress UI so it does not look frozen.
- Keep #197 as the central issue and #207/#208 as focused action issues.
