namespace eval rsc {}

proc rsc::output_path {name} {
    return [file join $::cfg(out) $name]
}

proc rsc::write_text {name value} {
    set stream [open [output_path $name] w]
    puts $stream $value
    close $stream
}
