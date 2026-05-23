"""
Disabled-by-default Kraken live execution client skeleton.

Slice 14B purpose:
- Create the structure for a future Kraken live execution client.
- Require the Slice 14A safety gate before any future executable action.
- Prove that default configuration blocks every live execution path.
- Avoid any real Kraken private execution endpoint call.

Important:
This module does NOT place live orders.
This module does NOT cancel live orders.
This module does NOT send private trading requests.
This module does NOT require trading, funding, or withdrawal permissions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Mapping

from tradingagents.execution.safety_config import LiveExecutionSafetyConfig


class LiveExecutionNotImplementedError(RuntimeError):
    """
    Raised after the safety gate if live execution is requested later.

    Slice 14B intentionally keeps this client as a blocked skeleton.
    """


@dataclass(frozen=True)
class KrakenLiveOrderRequest:
    """
    Structured request model for a future Kraken live order.

    This model is safe because it is only data. It does not call Kraken.
    """

    pair: str
    side: str
    order_type: str
    volume: Decimal
    price: Decimal | None = None
    client_reference: str = ""
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        """Validate request shape without executing anything."""

        if not self.pair.strip():
            raise ValueError("pair is required.")

        if self.side.lower() not in {"buy", "sell"}:
            raise ValueError("side must be buy or sell.")

        if not self.order_type.strip():
            raise ValueError("order_type is required.")

        if self.volume <= Decimal("0"):
            raise ValueError("volume must be greater than zero.")

        if self.price is not None and self.price <= Decimal("0"):
            raise ValueError("price must be greater than zero when provided.")


@dataclass(frozen=True)
class KrakenLiveCancelRequest:
    """
    Structured request model for a future Kraken live cancellation.

    This model is safe because it is only data. It does not call Kraken.
    """

    transaction_id: str
    client_reference: str = ""
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        """Validate request shape without executing anything."""

        if not self.transaction_id.strip():
            raise ValueError("transaction_id is required.")


@dataclass(frozen=True)
class KrakenLiveExecutionClient:
    """
    Disabled-by-default skeleton for future Kraken live execution.

    A caller must pass a LiveExecutionSafetyConfig. With the default safety config,
    every executable method is blocked before any future client operation could run.
    """

    safety_config: LiveExecutionSafetyConfig
    private_client: Any | None = None

    def submit_order(self, request: KrakenLiveOrderRequest) -> None:
        """
        Future live order submission entry point.

        In Slice 14B, this is intentionally blocked by the safety gate and then
        intentionally not implemented even if a future unsafe config is supplied.
        """

        request.validate()
        self.safety_config.assert_live_execution_allowed("kraken execution request")
        raise LiveExecutionNotImplementedError(
            "Live order submission is intentionally not implemented in Slice 14B."
        )

    def cancel_order(self, request: KrakenLiveCancelRequest) -> None:
        """
        Future live cancellation entry point.

        In Slice 14B, this is intentionally blocked by the safety gate and then
        intentionally not implemented even if a future unsafe config is supplied.
        """

        request.validate()
        self.safety_config.assert_live_execution_allowed("kraken cancellation request")
        raise LiveExecutionNotImplementedError(
            "Live order cancellation is intentionally not implemented in Slice 14B."
        )

    def safe_report(self) -> dict[str, str | bool]:
        """Return safe-to-log client status without secrets or credentials."""

        return {
            "client": "KrakenLiveExecutionClient",
            "live_execution_client_skeleton": True,
            "private_client_present": self.private_client is not None,
            "live_trading_enabled": self.safety_config.live_trading_enabled,
            "kill_switch": self.safety_config.kill_switch,
            "max_live_trade_value": str(self.safety_config.max_live_trade_value),
            "secrets_included": False,
        }
