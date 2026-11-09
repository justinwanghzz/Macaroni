# Hosted compiler compatibility — 0.5.6 / build 16

The GitHub macos-15 job failed while compiling RotationPreview, reporting an ambiguous cos overload. The preview expression mixed a Double angle with CGFloat image geometry, and local/newer compiler inference had accepted it. Radians and Darwin trigonometry now explicitly use Double; magnitudes are converted to CGFloat before geometry arithmetic. Rotation behavior is unchanged.

No public diagnostic/log-upload workflow was added. Diagnosis used the workflow log supplied by the user. Existing CI tests/package steps remain the validation path.
