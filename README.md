# Arcanis Games: Core Systems 

This repository contains the backend state management, custom physics engines, and procedural generation code

**Voxel Generation**
* **Dynamic Frame Budgeting:** Utilizes a custom asynchronous task scheduler (`BlockQueue`) that reads active server heartbeat times to dynamically allocate processing budgets, ensuring complex block destructions never drop server frame rates
* **Procedural Noise & Caching:** Maps terrain using deterministic 3D Perlin noise (`CaveGenerator`) combined with a strictly managed memory cache to recycle block data and prevent memory leaks
* **Spatial Hashing:** Packs 3D coordinate vectors into single integer keys (`GridUtils`) for fast O(1) dictionary lookups for best optimization
* 
### 📂 Repository Structure
* `/Minerite` - Voxel generation algorithms
* `/Tennis` - Match state machines, scoring logic, raycast spatial tracking hitboxes
