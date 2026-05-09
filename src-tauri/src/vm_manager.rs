use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VmAllocation {
    pub cpu_cap: i32,
    pub ram_cap_gb: i32,
    pub end_time: Instant,
}

pub struct VmManager {
    pub vm_name: String,
    pub max_host_ram_gb: i32,
    pub current_allocation: Arc<Mutex<Option<VmAllocation>>>,
}

impl VmManager {
    pub fn new(vm_name: String) -> Self {
        let total_ram = Self::get_host_ram();
        let max_cap = if total_ram >= 16 { 16 } else { 8 };
        
        Self {
            vm_name,
            max_host_ram_gb: max_cap,
            current_allocation: Arc::new(Mutex::new(None)),
        }
    }

    fn get_host_ram() -> i32 {
        let output = Command::new("powershell")
            .args(["-Command", "(Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB"])
            .output()
            .ok();
        
        if let Some(out) = output {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            s.parse::<f64>().unwrap_or(8.0) as i32
        } else {
            8
        }
    }

    pub fn start_monitoring(self: Arc<Self>) {
        tokio::spawn(async move {
            loop {
                self.tick();
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        });
    }

    fn tick(&self) {
        let mut alloc_guard = self.current_allocation.lock().unwrap();
        
        if let Some(alloc) = alloc_guard.as_ref() {
            if Instant::now() > alloc.end_time {
                // Allocation expired, reset to auto-scale
                *alloc_guard = None;
                self.apply_caps(10, 1); // Reset to low idle
            } else {
                // Apply manual allocation
                self.apply_caps(alloc.cpu_cap, alloc.ram_cap_gb);
            }
        } else {
            // Auto-scale logic (simplified: check if VM is running and apply modest defaults)
            // In a real scenario, we'd poll Get-VM and adjust based on CPU load.
            self.apply_caps(40, 4); 
        }
    }

    fn apply_caps(&self, cpu_cap: i32, ram_cap_gb: i32) {
        let ram_bytes = (ram_cap_gb as u64) * 1024 * 1024 * 1024;
        let _ = Command::new("powershell")
            .args([
                "-Command",
                &format!(
                    "Set-VMProcessor -VMName {} -Maximum {}; Set-VMMemory -VMName {} -MaximumBytes {}",
                    self.vm_name, cpu_cap, self.vm_name, ram_bytes
                ),
            ])
            .spawn();
    }

    pub fn request_allocation(&self, cpu_cap: i32, ram_cap_gb: i32, duration_secs: u64) {
        let mut alloc_guard = self.current_allocation.lock().unwrap();
        *alloc_guard = Some(VmAllocation {
            cpu_cap,
            ram_cap_gb: std::cmp::min(ram_cap_gb, self.max_host_ram_gb),
            end_time: Instant::now() + Duration::from_secs(duration_secs),
        });
    }
}
