"""macOS / Apple Silicon (Metal) support for Cookbook hardware-fit.

Covers the Metal-specific behavior added for Apple Silicon and locks in the
guarantee that non-macOS (Linux/Windows) detection is unchanged.
"""

from services.hwfit import hardware
from services.hwfit.fit import rank_models


def _metal_system(ram_gb=16.0, vram_gb=10.7):
    return {
        "has_gpu": True,
        "backend": "metal",
        "gpu_name": "Apple M2",
        "gpu_vram_gb": vram_gb,
        "gpu_count": 1,
        "available_ram_gb": ram_gb * 0.7,
        "total_ram_gb": ram_gb,
        "unified_memory": True,
    }


def _fake_sysctl(brand="Apple M2 Pro", memsize_gb=32, wired_mb=None):
    def run(cmd):
        joined = " ".join(cmd)
        if "machdep.cpu.brand_string" in joined:
            return brand
        if "hw.memsize" in joined:
            return str(int(memsize_gb * 1024**3))
        if "iogpu.wired_limit_mb" in joined:
            return str(wired_mb) if wired_mb is not None else None
        return None
    return run


def test_mlx_models_hidden_on_metal():
    """MLX-quantized models can't be served by llama.cpp or Ollama (the only
    Metal-capable engines Odysseus generates), so they must never be recommended
    on Apple Silicon — even though the catalog tags them as Apple-only."""
    results = rank_models(_metal_system(), limit=900)
    mlx = [m for m in results if str(m.get("quant", "")).startswith("mlx-")]
    assert mlx == [], f"MLX models surfaced but cannot be served: {[m['name'] for m in mlx]}"


def test_mlx_hidden_on_cuda_backend_unchanged():
    """Regression guard: Linux/CUDA users never saw MLX before and still don't."""
    sys_cuda = {
        "has_gpu": True, "backend": "cuda", "gpu_name": "NVIDIA RTX 4090",
        "gpu_vram_gb": 24.0, "gpu_count": 1, "available_ram_gb": 32.0, "total_ram_gb": 64.0,
    }
    mlx = [m for m in rank_models(sys_cuda, limit=900) if str(m.get("quant", "")).startswith("mlx-")]
    assert mlx == []


def test_apple_silicon_detected_as_metal(monkeypatch):
    """On local Apple Silicon, detection reports a Metal GPU with a RAM-scaled
    unified-memory budget."""
    monkeypatch.setattr(hardware, "_remote_host", None)
    monkeypatch.setattr(hardware.platform, "system", lambda: "Darwin")
    monkeypatch.setattr(hardware.platform, "machine", lambda: "arm64")
    monkeypatch.setattr(hardware, "_run", _fake_sysctl(memsize_gb=32))

    info = hardware._detect_apple_silicon()
    assert info is not None
    assert info["backend"] == "metal"
    assert info["gpu_name"] == "Apple M2 Pro"
    assert info["unified_memory"] is True
    assert info["gpu_vram_gb"] == 24.0  # 32GB * 0.75


def test_apple_silicon_skipped_on_linux(monkeypatch):
    """Guarantee Linux detection is untouched: the Metal probe bails immediately."""
    monkeypatch.setattr(hardware, "_remote_host", None)
    monkeypatch.setattr(hardware.platform, "system", lambda: "Linux")
    monkeypatch.setattr(hardware.platform, "machine", lambda: "x86_64")
    monkeypatch.setattr(hardware, "_run", _fake_sysctl())
    assert hardware._detect_apple_silicon() is None


def test_intel_mac_skipped(monkeypatch):
    """Intel Macs have no Metal GPU worth serving LLMs on — fall through to CPU."""
    monkeypatch.setattr(hardware, "_remote_host", None)
    monkeypatch.setattr(hardware.platform, "system", lambda: "Darwin")
    monkeypatch.setattr(hardware.platform, "machine", lambda: "x86_64")
    monkeypatch.setattr(hardware, "_run", _fake_sysctl())
    assert hardware._detect_apple_silicon() is None


def test_detect_system_propagates_unified_memory(monkeypatch):
    """The unified_memory flag set by GPU detection must survive into the
    system dict so the API and UI can report it (it was being dropped)."""
    monkeypatch.setattr(hardware, "_detect_apple_silicon", lambda: {
        "gpu_name": "Apple M4", "gpu_vram_gb": 10.7, "gpu_count": 1,
        "gpus": [], "gpu_groups": [], "homogeneous": True,
        "backend": "metal", "unified_memory": True,
    })
    monkeypatch.setattr(hardware, "_get_ram_gb", lambda: 16.0)
    monkeypatch.setattr(hardware, "_get_available_ram_gb", lambda: 11.0)
    monkeypatch.setattr(hardware, "_get_cpu_count", lambda: 10)
    monkeypatch.setattr(hardware, "_get_cpu_name", lambda: "Apple M4")

    s = hardware.detect_system(fresh=True)
    assert s["backend"] == "metal"
    assert s.get("unified_memory") is True
