"""카드사 목록의 새 카드와 사라진 카드. 작업 003 과제 16."""

from cherry_core.pipeline.lists import list_changes


def test_first_list_is_only_a_baseline():
    assert list_changes(None, ["현대카드M", "the Green"], set()) == ([], [])


def test_new_and_removed_names():
    previous = ["현대카드M", "the Green Edition4", "ZERO Edition3"]
    current = ["현대카드M", "the Green Edition4", "현대카드 X"]
    assert list_changes(previous, current, set()) == (["현대카드 X"], ["ZERO Edition3"])


def test_spacing_and_case_are_the_same_name():
    assert list_changes(["현대카드 M"], ["현대카드m"], set()) == ([], [])


def test_catalog_names_are_not_new_cards():
    # 카탈로그의 name과 search_names에 있는 이름은 이미 아는 카드다
    assert list_changes(["현대카드M"], ["현대카드M", "현대카드 ZERO Edition3"], {"현대카드ZERO Edition3"}) == ([], [])
