"""카드사 목록의 새 카드와 사라진 카드. 작업 003 과제 16.

모델은 지난 목록과 비교해 바뀐 줄에서만 이름을 뽑는다. 2026-10-01 개발용 시험의 모양을 줄였다.
"""

from cherry_core.pipeline.lists import list_changes

OLD = "신용카드\n체크카드\nSync카드 | 연회비 1만원\nMOVING카드\n가족카드"
NEW = "신용카드\n체크카드\n체리시험카드 HANA | 연회비 1만원\nMOVING카드\n가족카드"


def test_swapped_name_is_one_new_and_one_gone():
    assert list_changes(OLD, NEW, ["Sync카드"], ["체리시험카드 HANA"], set()) == (["체리시험카드 HANA"], ["Sync카드"])


def test_names_not_in_the_text_are_dropped():
    # 모델이 "카카오뱅크"를 "카카오뱱크"로 잘못 쓴 이름이 나왔다
    assert list_changes(OLD, NEW, [], ["체리시험카드 HANA", "카카오뱱크 카드"], set()) == (["체리시험카드 HANA"], [])


def test_menu_words_in_both_texts_are_not_cards():
    # 바뀐 줄에서 "카드" 같은 메뉴 글을 뽑아도 옛 글에도 있어 새 카드가 아니다
    assert list_changes(OLD, NEW, ["카드"], ["체리시험카드 HANA", "카드", "신용카드"], set()) == (
        ["체리시험카드 HANA"],
        [],
    )


def test_name_still_elsewhere_is_not_gone():
    # 현대 목록처럼 같은 이름이 메뉴에도 나오면, 한 줄이 바뀌어도 사라진 것이 아니다
    old = "MOVING카드\nMOVING카드 | 1만원 할인"
    new = "MOVING카드\nMOVING카드 | 2만원 할인 행사"
    assert list_changes(old, new, ["MOVING카드"], ["MOVING카드"], set()) == ([], [])


def test_catalog_names_are_not_new_cards():
    assert list_changes(OLD, NEW, [], ["체리시험카드 HANA"], {"체리시험카드HANA"}) == ([], [])


def test_spacing_and_case_are_the_same_name():
    assert list_changes("현대카드 M", "현대카드m 새 혜택", [], ["현대카드M"], set()) == ([], [])


def test_shorter_name_inside_a_longer_one_is_dropped():
    # 2026-10-01 개발용 시험에서 모델이 "체리시험카드 HYUNDAI"와 그 앞부분 "체리시험카드"를 함께 뽑았다
    old, new = "Summit CE | 연회비", "체리시험카드 HYUNDAI | 연회비"
    assert list_changes(old, new, ["Summit CE"], ["체리시험카드 HYUNDAI", "체리시험카드"], set()) == (
        ["체리시험카드 HYUNDAI"],
        ["Summit CE"],
    )
