import AppKit

// Economic Calendar — native macOS desktop widget.
//
// Force this app's localization to en-US so investing.com renders the English
// ("Weekday, Month D, YYYY") date headers the extraction JS expects. Only
// affects this accessory app, not the system.

UserDefaults.standard.register(defaults: ["AppleLanguages": ["en-US"]])

let arguments = CommandLine.arguments

if arguments.contains("--print-cache") {
    PrintCacheTool.run()
    exit(0)
}

if arguments.contains("--parse-test") {
    PrintCacheTool.parseTest()
    exit(0)
}

if arguments.contains("--help") {
    print("""
    Economic Calendar — native macOS desktop widget

    Usage: EconomicCalendar [options]
      (no options)   Launch the widget
      --fetch-once   Run one fetch cycle, write cache.json, print the table, exit
      --print-cache  Print the contents of cache.json and exit
      --help         Show this help
    """)
    exit(0)
}

let delegate = AppDelegate(fetchOnce: arguments.contains("--fetch-once"))
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
