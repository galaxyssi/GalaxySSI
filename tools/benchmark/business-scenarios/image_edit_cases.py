"""Image edit workloads and private scoring oracles; no oracle is sent as a prompt."""

IMAGE_CASES = {
    32: ("质检记录原图纠错", "复核记录中的计算，只在错误旁批注", False),
    44: ("手写算术作业逐题批改", "批改手写答案，正确题不改，错误题旁写正确答案", True),
    48: ("界面截图问题定位批注", "标出界面中错误的计算结果，使用简短箭头说明", False),
    52: ("监控数据截图解释与标记", "核对监控统计数据，在异常计算旁标记并总结", False),
    60: ("商品报价图片复核", "复核报价计算，在原图上更正算错的金额", False),
    68: ("手写备餐统计批注", "识别手写统计结果，在原图上批注错误", True),
    72: ("展会物资表笔迹批注", "复核物资计算，在错误旁添加手写风格批注", False),
    84: ("手写采收记录校核", "核对手写采收合计，读不清的单独标为待确认", True),
    96: ("实验记录图片总结", "读出实验记录，核对计算，简要总结并在原图标错", True),
    100: ("双图对照与原图批注", "对照两张记录，把第二张变化项标在第一张上，同时纠正计算", False),
}


def image_case(number, domain):
    title, instruction, handwritten = IMAGE_CASES[number]
    code = f"ART-{number:03d}"
    # The stroke-based handwriting is synthetic, not evidence of real handwriting robustness.
    rows = [{"label": "1. 12 + 7 =", "answer": "18"},
            {"label": "2. 9 x 6 =", "answer": "54"},
            {"label": "3. 40 - 16 =", "answer": "26"},
            {"label": "4. 36 / 4 =", "answer": "9"},
            {"label": "5. 15 + 8 =", "answer": "?"}]
    fixtures = [{"title": title, "code": code, "rows": rows,
                 "handwritten": handwritten, "synthetic": True}]
    if number == 100:
        fixtures.append({"title": "第二张修订记录", "code": code + "-B",
                         "rows": [dict(r, answer="19") if i == 0 else dict(r)
                                  for i, r in enumerate(rows)],
                         "handwritten": False, "synthetic": True})
    prompts = [
        ("annotate_original", instruction + "。只交付一张批注后的第一张原图，不另做答题卡。"),
        ("minimal_marks", "删除大框、涂满背景和重复说明，只保留必要的小批注；原题和原答案仍清楚可读。"),
        ("change_ink", "不改变内容和位置，把纠错笔迹改成深红色，正确内容不加标记。"),
        ("handwritten_annotation", "把纠错数字改为清晰的手写风格笔迹，不重写题目，不冒充真实人的签名。"),
        ("illegible_abstention", "第五项原答案不清楚，标为识别不清、待确认，不能直接判错；区分算出的答案与识别到的原答案。"),
        ("undo_one_mark", "仅撤销第三项的批注，其他批注保留，原图内容不变。"),
        ("restore_one_mark", "恢复第三项刚才撤销的批注，保留其余版式和深红笔迹。"),
        ("summary_only", "只用中文文字总结目前结果，不附任何图片或文件；分别说清错误、正确和无法辨认的项。"),
        ("verify_original", "重新输出一张最终批注图；与原图核对，不能改变原题、原答案或裁掉内容，不重复叠加批注。"),
        ("inspect_detail", "保持原图尺寸，调整太细或遮挡文字的笔迹，让手机放大后清楚；只交付一张图。"),
        ("final_delivery", "只交付当前一张最终批注图，不附原图、旧版本、答题卡或额外图片；说明最多两句话。"),
    ]
    turns = []
    for i, (kind, request) in enumerate(prompts):
        summary = kind == "summary_only"
        turns.append({"index": i, "kind": kind, "expected": {},
            "prompt": request + ("" if summary else
                f"\n使用已有原图，文件名包含{code}-v{i+1:02d}，不要覆盖旧版。"
                "通过图片附件交付，不能只给本机路径或代码。不要联网或执行真实业务操作。"),
            "artifact_expectations": {
                "extensions": [],
                "image_extensions": [] if summary else ["png", "jpg", "jpeg"],
                "name_prefix": f"{code}-v{i+1:02d}",
                "preview_required": not summary, "text_only": summary,
                "max_image_count": 0 if summary else 1,
                "source_record": code, "requires_human_review": True,
                "preserve_original": True, "expected_dimensions": [1200, 1600],
                "annotation_oracle": {"wrong_rows": [1, 3], "correct_rows": [2, 4],
                    "unreadable_rows": [5], "answers": {"1": 19, "2": 54, "3": 24, "4": 9, "5": 23},
                    "visible_corrections": [1] if i == 5 else [1, 3]},
            }})
    return {"id": f"A{number:03d}", "name": title, "domain": domain,
        "modality": "artifact_png", "workflow": "image_edit", "fixtures": fixtures,
        "fixture_style": "annotation_sheet", "turns": turns,
        "background_turns": [2, 5, 8], "restore_turns": [6], "latency_target_ms": 180000,
        "review": ["原图保留且不遮挡", "错误与识别不清分开", "批注坐标及笔迹", "单图交付",
                   "撤销和恢复", "总结事实正确", "缩略图放大和保存"],
        "handwriting_scope": "Synthetic digit strokes only; real human handwriting requires additional device cases."}
