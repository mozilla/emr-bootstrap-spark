------------------------

Testing checklist:

- [ ] Deploy your changes to the staging location ([see README](https://github.com/mozilla/emr-bootstrap-spark#deploy-to-aws-via-ansible))
- [ ] Launch an [ATMO stage](https://atmo.stage.mozaws.net/) cluster and check for startup failures
- [ ] Ensure that the [Telemetry Hello World notebook](https://github.com/mozilla/mozilla-reports/blob/master/tutorials/telemetry_hello_world.kp/orig_src/Telemetry%20Hello%20World.ipynb) can run on your ATMO cluster without errors

The above checks are not exhaustive, nor are they strictly required before merging,
but they are useful to catch many  common error cases
such as incompatibilities when updating python library versions.
