# Ansi — privacy policy

Ansi is a recipe, meal-planning and shopping app built for one household and
the few people it invites. There are no ads, no analytics and no tracking, and
no data is sold or shared for marketing.

## What Ansi stores

- **Your account:** your email address and, if you sign in with Google, the
  name on your Google account.
- **Your household's content:** recipes, ingredients, meal plans, shopping
  lists, prices and receipts you scan or type in.
- **What you ate:** which planned meals you said you ate and when, what you
  had instead, and what became of a batch's leftovers. Like the rest of the
  household's content, your household can read it. The app shows the other
  members only whether you ticked a meal, not what you had instead.

This is stored with **Supabase** (database and sign-in) and synced between
your devices by **PowerSync**. Both act only as hosting providers for Ansi.
All traffic is encrypted in transit (HTTPS). Only members of your household
can read your household's data.

## What is sent to other services, and when

- **Anthropic (Claude):** when you import a recipe from a web page or a photo,
  or scan a receipt, that page text or photo is sent to Anthropic's API to be
  read and turned into structured data. Photos are processed for that one
  request and are not stored by Ansi. Under Anthropic's commercial terms, API
  inputs are not used to train their models. Import is only switched on for
  invited households.
- **Anthropic (Claude), when you ask Ansi a question:** the words of your
  question, what is on your screen (the recipe and the servings shown, or the
  week on the Week, Cook or Shop tab, and today's date), the conversation so
  far, and what Ansi looks up to answer — recipe lines or steps, the week's
  meals with the names of who eats them, the cook plan, shopping-list rows,
  ingredient names — are sent to Anthropic's API. Ansi's server stores none of it, and the
  conversation itself stays on your device until it is cleared. Like import,
  it is only switched on for invited households.
- **Open Food Facts:** when you scan a barcode, the barcode number (and
  nothing else about you) is looked up in the public Open Food Facts
  database.
- **Recipe websites:** when you import a recipe by link, Ansi's server fetches
  that page. The site sees a request from the server, not from your device.

## Camera

The camera is used only when you choose to scan a barcode, photograph a
recipe or scan a receipt.

## Microphone

The microphone is used only when you tap the mic in Ask Ansi. Your phone's own
speech recogniser turns what you say into text — on the device where the phone
supports it, otherwise through the recognition service your phone uses (Google's,
on most Android phones). Ansi receives only the text, never the audio. Answers
read aloud use your phone's own text-to-speech.

## Notifications and kitchen timers

A timer you start on a recipe is kept only on the device you started it on;
it is never sent to a server or to the other people in your household. When it
ends, the device itself shows the notification — nothing is sent anywhere to
make it ring. Ansi asks for permission to send notifications (and, on Android,
to ring on time) the first time you start a timer, and works without it: the
timer then sounds only while Ansi is open.

## Deleting your account

Email **wkndvibes@proton.me** from the address you sign in with and ask for your
account to be deleted. Your account and, if you are its last member, your
household's data are deleted within 30 days. You can also delete individual
recipes, plans and receipts in the app at any time.

## Children

Ansi is not directed at children under 13.

## Contact

Questions: **wkndvibes@proton.me**.

This policy describes the app as it currently works; if that changes, this
page changes with it.
