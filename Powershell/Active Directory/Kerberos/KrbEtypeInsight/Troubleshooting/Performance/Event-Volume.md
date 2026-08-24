# Event volume

A busy domain controller produces 4769 events at a rate that makes "collect everything and
filter later" untenable. Tens of millions a week is ordinary.

## Where the time goes

Roughly **2.8 ms per event warm**, and **5.9 ms on the first run of a session**. Both numbers
matter, and quoting only one of them is how the earlier version of this page got the breakdown
wrong.

| Stage | Warm | Share |
|---|---|---|
| `Get-WinEvent` itself — RPC or file read | 1.61 ms | ~57% |
| `Get-KrbEvent` overhead — record to XML, filtering, emit | 0.37 ms | ~13% |
| `ConvertFrom-KrbEventRecord` — XML parse and all decoding | 0.82 ms | ~29% |

At that rate the default `-MaxEvents 50000` takes a little over two minutes per controller.

### Why the share moves, and why it is not 40%

An earlier revision of this page put `Get-WinEvent` at ~40% and the decode work at ~45%. That
came from a single cold measurement, and it is misleading, because the two halves warm up at
completely different rates.

`Get-WinEvent` is I/O bound. It costs about 966 ms per 600 events on the first run and on the
eighth — tiered JIT has nothing to offer it. The decode path is pure managed code and gets
roughly four times faster as it warms. Eight consecutive runs of 600 events:

```text
5.85, 4.22, 2.95, 2.76, 2.75, 2.83, 2.80, 2.84   ms per event
```

So the `Get-WinEvent` share **rises** from 28% cold to 57% warm, not because collection got
slower but because everything around it got faster. "3.6 ms per event, of which 35% is
`Get-WinEvent`" described a half-warmed run and was true at no point you would actually
measure.

The practical consequence: on a real collection of tens of thousands of events, nearly every
event is decoded warm, so **plan against 2.8 ms and a 57% I/O share**. That is also why the
archive-to-`.evtx` pattern below helps less than it looks — it attacks the 57%, but it cannot
remove it.

## Reduce what you ask for

**Narrow the event ID.** The cheapest optimisation available, and often the right one:

| Question | Events |
|---|---|
| What have services been presenting? | `4769` |
| What do clients advertise? | `4768` |
| What is already failing? | `4771` |

```powershell
Get-KrbEvent -EventId 4769 -MaxEvents 20000
```

**Keep the window at 30 days but cap the count.** A representative sample from each controller
is nearly always a better basis for an assessment than an exhaustive read of one. `-MaxEvents`
is applied per source and takes the newest events.

**Do not filter after collection.** Event ID and time window go into the `FilterHashtable`,
where the log service evaluates them on the remote controller before a record crosses the
network. The same filtering with `Where-Object` afterwards transfers every record and is slower
by orders of magnitude - and the difference is invisible in the output.

## The archive pattern

For a large estate this is the intended approach. `wevtutil` exports in seconds because nothing
leaves the machine.

On each controller:

```powershell
$out = "C:\Temp\$env:COMPUTERNAME-krb-$(Get-Date -Format yyyyMMdd).evtx"
wevtutil epl Security $out "/q:*[System[(EventID=4768 or EventID=4769 or EventID=4771)]]"
```

Then, anywhere - including a workstation with no domain connectivity:

```powershell
Get-ChildItem \\fileserver\krbaudit\*.evtx | Get-KrbEvent -MaxEvents 0 | Get-KrbEtypeRisk -Offline
```

`-MaxEvents 0` means unlimited. Use it only against archived files; applying no limit to a live
controller's Security log is a request to transfer the entire log.

To bound the export by record range rather than exporting the whole log:

```powershell
$floor = (Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4768, 4769, 4771 } `
              -MaxEvents 5000 | Measure-Object RecordId -Minimum).Minimum

$q = "/q:*[System[(EventID=4768 or EventID=4769 or EventID=4771) and (EventRecordID>=$floor)]]"
wevtutil epl Security C:\Temp\slice.evtx $q
```

Note that Security log record IDs are shared with every other audit category, so a
Kerberos-only slice of 5000 events can span a hundred thousand record IDs on a busy machine.
Derive the floor from the events, never from a fixed offset.

## Memory during correlation

`Get-KrbEtypeRisk` buffers events in memory, because a per-principal view cannot be built from a
stream. Peak is roughly 2 KB per event - about 200 MB for 100,000 events.

Beyond a few hundred thousand, assess one controller's archive at a time and merge the resulting
risk objects:

```powershell
$all = foreach ($file in Get-ChildItem \\fileserver\krbaudit\*.evtx) {
    Get-KrbEvent -Path $file.FullName -MaxEvents 0 | Get-KrbEtypeRisk -Offline
}
$all | Sort-Object RiskScore -Descending | Export-KrbEtypeReport -Path .\merged.html
```

Merging per-controller assessments splits a principal's evidence across objects. For the final
report, prefer one correlation run over the combined event set if it fits in memory.

## Controllers are read sequentially

Deliberately. Parallel reads across controllers would need the decode to happen in worker
runspaces, where `EventLogRecord` objects tied to a reader session become unreliable. The
archive pattern above is the supported way to parallelise: export concurrently, decode once.

## Related

- [No events collected](../Common/No-Events-Collected.md)
- [Directory query performance](Directory-Queries.md)
