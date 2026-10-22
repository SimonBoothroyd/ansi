package io.ansi.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * What Health Connect opens when someone asks why Ansi wants health access:
 * Android requires every app that asks for a health permission to answer.
 * Ansi's answer is its privacy policy, so this opens it and gets out of the
 * way.
 */
class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL)))
        finish()
    }

    companion object {
        const val PRIVACY_POLICY_URL = "https://getansi.app/privacy"
    }
}
