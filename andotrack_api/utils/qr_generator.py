"""
andotrack_api/utils/qr_generator.py

Generates a unique QR token per runner-race registration and
encodes it as a base64 PNG that the Flutter app can render directly.

QR payload format (encoded inside the QR image):
    ANDOTRACK:{race_id}:{runner_id}:{uuid4_hex}

The organizer app scans the QR, reads this string, and posts the
qr_token to POST /races/{race_id}/checkin.
"""

import uuid
import base64
import io
import qrcode
from qrcode.image.pil import PilImage


def generate_qr_token(race_id: int, runner_id: int) -> str:
    """
    Create a unique, unguessable token tied to one runner + race.
    Format: ANDOTRACK:{race_id}:{runner_id}:{uuid4_hex}
    """
    unique = uuid.uuid4().hex
    return f"ANDOTRACK:{race_id}:{runner_id}:{unique}"


def token_to_base64_png(token: str, box_size: int = 10, border: int = 4) -> str:
    """
    Encode a token string into a QR code image and return it as a
    base64-encoded PNG string.

    Flutter usage:
        Image.memory(base64Decode(qr_image_base64))
    """
    qr = qrcode.QRCode(
        version=None,           # auto-size
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=box_size,
        border=border,
    )
    qr.add_data(token)
    qr.make(fit=True)

    img: PilImage = qr.make_image(fill_color="black", back_color="white")

    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    buffer.seek(0)

    return base64.b64encode(buffer.read()).decode("utf-8")


def generate_registration_qr(race_id: int, runner_id: int) -> tuple[str, str]:
    """
    Convenience function — returns (qr_token, qr_image_base64).
    Call this once on registration and store qr_token in MySQL.
    """
    token = generate_qr_token(race_id, runner_id)
    image_b64 = token_to_base64_png(token)
    return token, image_b64


def parse_qr_token(token: str) -> dict | None:
    """
    Parse a scanned QR token back into its components.
    Returns None if the token format is invalid.

    Example:
        parse_qr_token("ANDOTRACK:1:42:abc123...")
        → {"race_id": 1, "runner_id": 42, "unique": "abc123..."}
    """
    try:
        parts = token.split(":")
        if len(parts) != 4 or parts[0] != "ANDOTRACK":
            return None
        return {
            "race_id":   int(parts[1]),
            "runner_id": int(parts[2]),
            "unique":    parts[3],
        }
    except (ValueError, IndexError):
        return None