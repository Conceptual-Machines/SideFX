#include "modulator.h"

namespace sidefx {

int ModulatorManager::createModulator(const std::string& name) {
    std::lock_guard<std::mutex> guard(mutex_);

    int id = nextId_++;
    auto mod = std::make_unique<Modulator>();
    mod->id = id;
    mod->name = name.empty() ? ("Modulator " + std::to_string(id)) : name;

    modulators_[id] = std::move(mod);
    return id;
}

void ModulatorManager::destroyModulator(int id) {
    std::lock_guard<std::mutex> guard(mutex_);
    modulators_.erase(id);
}

Modulator* ModulatorManager::getModulator(int id) {
    std::lock_guard<std::mutex> guard(mutex_);
    auto it = modulators_.find(id);
    if (it != modulators_.end()) {
        return it->second.get();
    }
    return nullptr;
}

std::vector<Modulator*> ModulatorManager::getActiveModulators() {
    std::lock_guard<std::mutex> guard(mutex_);
    std::vector<Modulator*> active;
    for (auto& pair : modulators_) {
        if (pair.second->enabled.load() && pair.second->target.isValid()) {
            active.push_back(pair.second.get());
        }
    }
    return active;
}

} // namespace sidefx

