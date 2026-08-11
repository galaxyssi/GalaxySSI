from device_identity import compose_device_display_name


def test_desktop_model_and_host_form_a_readable_unique_name():
    assert compose_device_display_name(
        model="ThinkPad T14 Gen 5",
        host_name="OFFICE-PC",
    ) == "ThinkPad T14 Gen 5 · OFFICE-PC"


def test_user_configured_name_has_priority():
    assert compose_device_display_name(
        explicit_name="Studio workstation",
        model="ThinkPad T14",
        host_name="OFFICE-PC",
    ) == "Studio workstation"


def test_identity_suffix_is_only_a_last_resort():
    assert compose_device_display_name(
        identity_fingerprint="a84cf19d",
    ) == "SignalASI Desktop · A84C"
