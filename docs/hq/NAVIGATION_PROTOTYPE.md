# HQ navigation prototype

The primary destinations are Overview (`#/`), Decisions (`#/work`), Work
(`#/work-status`) and Studio (`#/design`). New request remains visible from
every page and opens the durable intake flow. A work card's old `#/work/<id>`
link, the `#/inbox` alias, studio deep links and the other existing routes keep
their addresses.

Two layouts can be compared with **Tools → Try compact sidebar / Try top bar**.
The choice persists in this browser. On a narrow screen HQ uses the top bar so
the content has room. The top bar leaves more horizontal space for the Decisions
artifact pane; the compact sidebar keeps destinations in one vertical scan on
a wide display. The top bar is the initial prototype preference, not a final
decision about Daniel's navigation.

The switchboard's `/api/surface` reading controls visibility. A parked route
leaves navigation and remains available at its old deep link as the parked-page
notice. When restored, it returns to its assigned navigation group, including
Studio if Studio itself was parked. Live secondary tools remain in Tools: the
design document, entities, animation lab, playtests, goals, bullpen, execution
queue and pillar status. Work lists in-progress, preparing, blocked and closed
cards even when they are not ready for a human decision. Decisions continues to
use the shared ready-for-human projection.
