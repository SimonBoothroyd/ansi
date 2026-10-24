package io.ansi.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Where the Google sign-in comes back to: the `io.ansi.app://login-callback`
 * deep link, fired from the Custom Tab the sign-in page opened in.
 *
 * The Custom Tab sits above [MainActivity] in Ansi's own task, and whether it
 * closes when the link fires depends on the flags the link arrives with:
 * Chrome happens to send CLEAR_TOP, but nothing obliges another Custom Tabs
 * browser to. So this hands the link to the [MainActivity] already running
 * with CLEAR_TOP | SINGLE_TOP itself: everything above it in the task is
 * finished (the tab closes) and the link arrives through onNewIntent, where
 * Supabase's link listener finishes the sign-in. NEW_TASK makes the system
 * find that task whichever task the browser started this in.
 *
 * A trampoline rather than making [MainActivity] singleTask: singleTask
 * clears the top of the task on every launch, so tapping the launcher icon
 * would also destroy a photo crop, a camera capture or a Health Connect
 * permission screen open over the app.
 */
class AuthCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction(intent.action)
                .setData(intent.data)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
        )
        finish()
    }
}
