- (2026-09-03) From the chief of staff's review of the release-guard work: a
  guard that must fail fast needs its own job that the expensive jobs depend
  on — placed inside a job that `needs: tests`, it fires only after the suite
  has already spent its fifteen minutes. The claim "fails in seconds" is
  measured from the tag, not from the step before the export.
