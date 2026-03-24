import Foundation
import Supabase

// Shared Supabase client — used by AuthManager and BaesideProvider.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://lhrsxckcqwjwmyajtxyi.supabase.co")!,
    supabaseKey: "sb_publishable_bme40W6ASv7Rikw31rjbzg_LyHj0kXM",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)
