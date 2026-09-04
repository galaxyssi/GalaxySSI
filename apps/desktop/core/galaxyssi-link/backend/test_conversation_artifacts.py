from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from conversation_artifacts import (
    conversation_has_visual_context,
    conversation_input_artifact_paths,
    conversation_output_artifact_paths,
    stage_conversation_artifacts,
    stage_conversation_input_artifacts,
)
from conversation_context import ContextAttachment, ContextMessage, MobileConversationContext
import task_workspace


class ConversationArtifactTests(unittest.TestCase):
    def test_visual_context_detects_image_metadata_without_file_bytes(self):
        context = MobileConversationContext(
            attachment_index=(
                ContextAttachment(
                    artifact_id="image-1",
                    kind="image",
                    name="homework.jpg",
                    mime_type="image/jpeg",
                ),
            ),
        )

        self.assertTrue(conversation_has_visual_context(context))

    def test_non_visual_context_does_not_force_multimodal_execution(self):
        context = MobileConversationContext(
            attachment_index=(
                ContextAttachment(
                    artifact_id="file-1",
                    kind="file",
                    name="notes.pdf",
                    mime_type="application/pdf",
                ),
            ),
        )

        self.assertFalse(conversation_has_visual_context(context))

    def test_prior_turn_attachment_is_restored_inside_current_task_workspace(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"GALAXYSSI_WORKSPACE_ROOT": temporary},
        ):
            source_root = task_workspace.task_workspace("prior-task", "codex")
            source = source_root / "downloads" / "input" / "01-homework.jpg"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(b"image-content")
            context = MobileConversationContext(
                conversation_id="conversation-1",
                messages=(
                    ContextMessage(
                        role="user",
                        content="Please review this\nAttachments: homework.jpg (image/jpeg)",
                        message_id="entry-1",
                        group_id="phone-turn-1",
                        attachments=(
                            ContextAttachment(
                                artifact_id="image-1",
                                kind="image",
                                name="homework.jpg",
                                mime_type="image/jpeg",
                                size_bytes=13,
                                message_id="entry-1",
                                group_id="phone-turn-1",
                            ),
                        ),
                    ),
                ),
            )
            history = [
                {
                    "task_id": "prior-task",
                    "client_turn_id": "phone-turn-1",
                    "created_at": 1,
                },
                {
                    "task_id": "unrelated-task",
                    "client_turn_id": "another-turn",
                    "created_at": 2,
                },
            ]

            resolved = conversation_input_artifact_paths(
                context,
                history,
                current_task_id="current-task",
            )
            staged = stage_conversation_input_artifacts("current-task", resolved)

            self.assertEqual([source.resolve()], resolved)
            self.assertEqual(1, len(staged))
            self.assertEqual("homework.jpg", staged[0].name)
            self.assertEqual(b"image-content", staged[0].read_bytes())
            self.assertTrue(
                staged[0].is_relative_to(
                    task_workspace.task_workspace("current-task").resolve()
                )
            )

    def test_unreferenced_turn_and_external_file_are_not_restored(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"GALAXYSSI_WORKSPACE_ROOT": temporary},
        ):
            source_root = task_workspace.task_workspace("prior-task", "codex")
            source = source_root / "downloads" / "input" / "01-private.txt"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("private", encoding="utf-8")
            external = Path(temporary).parent / "external-galaxyssi-test.txt"
            external.write_text("external", encoding="utf-8")
            try:
                context = MobileConversationContext(
                    conversation_id="conversation-1",
                    messages=(
                        ContextMessage(
                            role="user",
                            content="No attachment reference",
                            message_id="entry-1",
                            group_id="different-turn",
                        ),
                    ),
                )

                resolved = conversation_input_artifact_paths(
                    context,
                    [{"task_id": "prior-task", "client_turn_id": "phone-turn-1"}],
                )
                staged = stage_conversation_input_artifacts(
                    "current-task",
                    [source, external],
                )

                self.assertEqual([], resolved)
                self.assertEqual([source.read_bytes()], [path.read_bytes() for path in staged])
                self.assertNotIn(external.name, [path.name for path in staged])
            finally:
                external.unlink(missing_ok=True)

    def test_compressed_image_names_and_multiple_inputs_match_the_same_turn(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"GALAXYSSI_WORKSPACE_ROOT": temporary},
        ):
            source_root = task_workspace.task_workspace("prior-task", "codex")
            input_root = source_root / "downloads" / "input"
            input_root.mkdir(parents=True, exist_ok=True)
            first = input_root / "01-homework.jpg"
            second = input_root / "02-notes.pdf"
            first.write_bytes(b"compressed-image")
            second.write_bytes(b"document")
            context = MobileConversationContext(
                conversation_id="conversation-1",
                attachment_index=(
                    ContextAttachment(
                        artifact_id="image-1",
                        kind="image",
                        name="homework.png",
                        mime_type="image/png",
                        group_id="phone-turn-1",
                    ),
                    ContextAttachment(
                        artifact_id="file-1",
                        kind="file",
                        name="notes.pdf",
                        mime_type="application/pdf",
                        group_id="phone-turn-1",
                    ),
                ),
            )

            resolved = conversation_input_artifact_paths(
                context,
                [{"task_id": "prior-task", "client_turn_id": "phone-turn-1"}],
            )

            self.assertEqual([first.resolve(), second.resolve()], resolved)

    def test_latest_output_is_restored_for_same_project_follow_up(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"GALAXYSSI_WORKSPACE_ROOT": temporary},
        ):
            source_root = task_workspace.task_workspace("prior-task", "codex")
            first = source_root / "outputs" / "SnakeGame-source.zip"
            latest = source_root / "outputs" / "SnakeGame-source-2.zip"
            first.write_bytes(b"first")
            latest.write_bytes(b"latest")
            os.utime(first, (1_700_000_000, 1_700_000_000))
            os.utime(latest, (1_700_000_010, 1_700_000_010))
            history = [{
                "task_id": "prior-task",
                "status": "completed",
                "completed_at": 2,
                "output_files": [
                    {"relative_path": "outputs/SnakeGame-source.zip"},
                    {"relative_path": "outputs/SnakeGame-source-2.zip"},
                ],
            }]

            resolved = conversation_output_artifact_paths(
                (
                    "[GALAXYSSI_CONVERSATION_CONTEXT_V1]\n"
                    "Earlier cards: SnakeGame-source.zip and SnakeGame-source-2.zip\n"
                    "[/GALAXYSSI_CONVERSATION_CONTEXT_V1]\n"
                    "\nCurrent user request:\n"
                    "Fix the startup UX, keep the same project, and return one updated source ZIP."
                ),
                history,
            )
            staged = stage_conversation_artifacts("current-task", resolved)

            self.assertEqual([latest.resolve()], resolved)
            self.assertEqual(["SnakeGame-source-2.zip"], [path.name for path in staged])
            self.assertEqual(b"latest", staged[0].read_bytes())

    def test_explicit_output_name_wins_over_newer_artifact(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"GALAXYSSI_WORKSPACE_ROOT": temporary},
        ):
            source_root = task_workspace.task_workspace("prior-task", "codex")
            requested = source_root / "outputs" / "report.csv"
            newer = source_root / "outputs" / "chart.png"
            requested.write_bytes(b"report")
            newer.write_bytes(b"chart")
            os.utime(requested, ns=(1, 1))
            os.utime(newer, ns=(2, 2))

            resolved = conversation_output_artifact_paths(
                "Update report.csv and return it.",
                [{"task_id": "prior-task", "status": "completed"}],
            )

            self.assertEqual([requested.resolve()], resolved)

    def test_unrelated_turn_does_not_restore_prior_output(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"GALAXYSSI_WORKSPACE_ROOT": temporary},
        ):
            source_root = task_workspace.task_workspace("prior-task", "codex")
            output = source_root / "outputs" / "private.zip"
            output.write_bytes(b"private")

            resolved = conversation_output_artifact_paths(
                "What is the weather today?",
                [{"task_id": "prior-task", "status": "completed"}],
            )

            self.assertEqual([], resolved)

    def test_failed_task_and_external_artifact_are_not_restored(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"GALAXYSSI_WORKSPACE_ROOT": temporary},
        ):
            source_root = task_workspace.task_workspace("failed-task", "codex")
            output = source_root / "outputs" / "failed.zip"
            output.write_bytes(b"failed")
            external = Path(temporary).parent / "external-output.zip"
            external.write_bytes(b"external")
            try:
                resolved = conversation_output_artifact_paths(
                    "Continue with the same project.",
                    [{"task_id": "failed-task", "status": "failed"}],
                )
                staged = stage_conversation_artifacts("current-task", [external])

                self.assertEqual([], resolved)
                self.assertEqual([], staged)
            finally:
                external.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
