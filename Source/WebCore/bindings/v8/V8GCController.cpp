/*
 * Copyright (C) 2009 Google Inc. All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 * 
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "V8GCController.h"

#include "ActiveDOMObject.h"
#include "Attr.h"
#include "DOMDataStore.h"
#include "DOMImplementation.h"
#include "HTMLImageElement.h"
#include "HTMLNames.h"
#include "MemoryUsageSupport.h"
#include "MessagePort.h"
#include "RetainedDOMInfo.h"
#include "RetainedObjectInfo.h"
#include "V8AbstractEventListener.h"
#include "V8Binding.h"
#include "V8CSSRule.h"
#include "V8CSSRuleList.h"
#include "V8CSSStyleDeclaration.h"
#include "V8DOMImplementation.h"
#include "V8MessagePort.h"
#include "V8RecursionScope.h"
#include "V8StyleSheet.h"
#include "V8StyleSheetList.h"
#include "WrapperTypeInfo.h"

#include <algorithm>
#include <utility>
#include <v8-debug.h>
#include <wtf/HashMap.h>
#include <wtf/StdLibExtras.h>
#include <wtf/UnusedParam.h>

#if PLATFORM(CHROMIUM)
#include "TraceEvent.h"
#endif

namespace WebCore {

#ifndef NDEBUG

class EnsureWeakDOMNodeVisitor : public DOMWrapperMap<Node>::Visitor {
public:
    void visitDOMWrapper(DOMDataStore*, Node*, v8::Persistent<v8::Object> wrapper)
    {
        ASSERT(wrapper.IsWeak());
    }
};

#endif // NDEBUG

template<typename T>
class ActiveDOMObjectPrologueVisitor : public DOMWrapperMap<T>::Visitor {
public:
    void visitDOMWrapper(DOMDataStore*, T* object, v8::Persistent<v8::Object> wrapper)
    {
        WrapperTypeInfo* typeInfo = V8DOMWrapper::domWrapperType(wrapper);  

        if (V8MessagePort::info.equals(typeInfo)) {
            // Mark each port as in-use if it's entangled. For simplicity's sake,
            // we assume all ports are remotely entangled, since the Chromium port
            // implementation can't tell the difference.
            MessagePort* port = reinterpret_cast<MessagePort*>(object);
            if (port->isEntangled() || port->hasPendingActivity())
                wrapper.ClearWeak();
            return;
        }

        ActiveDOMObject* activeDOMObject = typeInfo->toActiveDOMObject(wrapper);
        if (activeDOMObject && activeDOMObject->hasPendingActivity())
            wrapper.ClearWeak();
    }
};

// Implements v8::RetainedObjectInfo.
class UnspecifiedGroup : public RetainedObjectInfo {
public:
    explicit UnspecifiedGroup(void* object)
        : m_object(object)
    {
        ASSERT(m_object);
    }
    
    virtual void Dispose() { delete this; }
  
    virtual bool IsEquivalent(v8::RetainedObjectInfo* other)
    {
        ASSERT(other);
        return other == this || static_cast<WebCore::RetainedObjectInfo*>(other)->GetEquivalenceClass() == this->GetEquivalenceClass();
    }

    virtual intptr_t GetHash()
    {
        return PtrHash<void*>::hash(m_object);
    }
    
    virtual const char* GetLabel()
    {
        return "Object group";
    }

    virtual intptr_t GetEquivalenceClass()
    {
        return reinterpret_cast<intptr_t>(m_object);
    }

private:
    void* m_object;
};

class GroupId {
public:
    GroupId() : m_type(NullType), m_groupId(0) {}
    GroupId(Node* node) : m_type(NodeType), m_node(node) {}
    GroupId(void* other) : m_type(OtherType), m_other(other) {}
    bool operator!() const { return m_type == NullType; }
    uintptr_t groupId() const { return m_groupId; }
    RetainedObjectInfo* createRetainedObjectInfo() const
    {
        switch (m_type) {
        case NullType:
            return 0;
        case NodeType:
            return new RetainedDOMInfo(m_node);
        case OtherType:
            return new UnspecifiedGroup(m_other);
        default:
            return 0;
        }
    }
    
private:
    enum Type {
        NullType,
        NodeType,
        OtherType
    };
    Type m_type;
    union {
        uintptr_t m_groupId;
        Node* m_node;
        void* m_other;
    };
};

class GrouperItem {
public:
    GrouperItem(GroupId groupId, v8::Persistent<v8::Object> wrapper) : m_groupId(groupId), m_wrapper(wrapper) {}
    uintptr_t groupId() const { return m_groupId.groupId(); }
    RetainedObjectInfo* createRetainedObjectInfo() const { return m_groupId.createRetainedObjectInfo(); }
    v8::Persistent<v8::Object> wrapper() const { return m_wrapper; }

private:
    GroupId m_groupId;
    v8::Persistent<v8::Object> m_wrapper;
};

bool operator<(const GrouperItem& a, const GrouperItem& b)
{
    return a.groupId() < b.groupId();
}

typedef Vector<GrouperItem> GrouperList;

// If the node is in document, put it in the ownerDocument's object group.
//
// If an image element was created by JavaScript "new Image",
// it is not in a document. However, if the load event has not
// been fired (still onloading), it is treated as in the document.
//
// Otherwise, the node is put in an object group identified by the root
// element of the tree to which it belongs.
static GroupId calculateGroupId(Node* node)
{
    if (node->inDocument() || (node->hasTagName(HTMLNames::imgTag) && static_cast<HTMLImageElement*>(node)->hasPendingActivity()))
        return GroupId(node->document());

    Node* root = node;
    if (node->isAttributeNode()) {
        root = static_cast<Attr*>(node)->ownerElement();
        // If the attribute has no element, no need to put it in the group,
        // because it'll always be a group of 1.
        if (!root)
            return GroupId();
    }
    while (Node* parent = root->parentOrHostNode())
        root = parent;

    return GroupId(root);
}

class ObjectVisitor : public DOMWrapperMap<void>::Visitor {
public:
    void visitDOMWrapper(DOMDataStore* store, void* object, v8::Persistent<v8::Object> wrapper)
    {
        V8DOMWrapper::domWrapperType(wrapper)->visitDOMWrapper(store, object, wrapper);
    }
};

class NodeVisitor : public DOMWrapperMap<Node>::Visitor {
public:
    void visitDOMWrapper(DOMDataStore*, Node* node, v8::Persistent<v8::Object> wrapper)
    {
        if (node->hasEventListeners()) {
            Vector<v8::Persistent<v8::Value> > listeners;
            EventListenerIterator iterator(node);
            while (EventListener* listener = iterator.nextListener()) {
                if (listener->type() != EventListener::JSEventListenerType)
                    continue;
                V8AbstractEventListener* v8listener = static_cast<V8AbstractEventListener*>(listener);
                if (!v8listener->hasExistingListenerObject())
                    continue;
                listeners.append(v8listener->existingListenerObjectPersistentHandle());
            }
            if (!listeners.isEmpty())
                v8::V8::AddImplicitReferences(wrapper, listeners.data(), listeners.size());
        }

        GroupId groupId = calculateGroupId(node);
        if (!groupId)
            return;
        m_grouper.append(GrouperItem(groupId, wrapper));
    }

    void applyGrouping()
    {
        // Group by sorting by the group id.
        std::sort(m_grouper.begin(), m_grouper.end());

        for (size_t i = 0; i < m_grouper.size(); ) {
            // Seek to the next key (or the end of the list).
            size_t nextKeyIndex = m_grouper.size();
            for (size_t j = i; j < m_grouper.size(); ++j) {
                if (m_grouper[i].groupId() != m_grouper[j].groupId()) {
                    nextKeyIndex = j;
                    break;
                }
            }

            ASSERT(nextKeyIndex > i);

            // We only care about a group if it has more than one object. If it only
            // has one object, it has nothing else that needs to be kept alive.
            if (nextKeyIndex - i <= 1) {
                i = nextKeyIndex;
                continue;
            }

            size_t rootIndex = i;
            
            Vector<v8::Persistent<v8::Value> > group;
            group.reserveCapacity(nextKeyIndex - i);
            for (; i < nextKeyIndex; ++i) {
                v8::Persistent<v8::Value> wrapper = m_grouper[i].wrapper();
                if (!wrapper.IsEmpty())
                    group.append(wrapper);
            }

            if (group.size() > 1)
                v8::V8::AddObjectGroup(&group[0], group.size(), m_grouper[rootIndex].createRetainedObjectInfo());

            ASSERT(i == nextKeyIndex);
        }
    }

private:
    GrouperList m_grouper;
};

// Create object groups for DOM tree nodes.
void V8GCController::gcPrologue()
{
    TRACE_EVENT_BEGIN0("v8", "GC");

    v8::HandleScope scope;

    ActiveDOMObjectPrologueVisitor<void> activeObjectVisitor;
    visitActiveDOMObjects(&activeObjectVisitor);
    ActiveDOMObjectPrologueVisitor<Node> activeNodeVisitor;
    visitActiveDOMNodes(&activeNodeVisitor);

    NodeVisitor nodeVisitor;
    visitDOMNodes(&nodeVisitor);
    visitActiveDOMNodes(&nodeVisitor);
    nodeVisitor.applyGrouping();

    ObjectVisitor objectVisitor;
    visitDOMObjects(&objectVisitor);

    V8PerIsolateData* data = V8PerIsolateData::current();
    data->stringCache()->clearOnGC();
}

class SpecialCaseEpilogueObjectHandler {
public:
    static bool process(void* object, v8::Persistent<v8::Object> wrapper, WrapperTypeInfo* typeInfo)
    {
        if (V8MessagePort::info.equals(typeInfo)) {
            MessagePort* port1 = static_cast<MessagePort*>(object);
            // We marked this port as reachable in GCPrologueVisitor.  Undo this now since the
            // port could be not reachable in the future if it gets disentangled (and also
            // GCPrologueVisitor expects to see all handles marked as weak).
            if ((!wrapper.IsWeak() && !wrapper.IsNearDeath()) || port1->hasPendingActivity())
                wrapper.MakeWeak(port1, &DOMDataStore::weakActiveDOMObjectCallback);
            return true;
        }
        return false;
    }
};

class SpecialCaseEpilogueNodeHandler {
public:
    static bool process(Node* object, v8::Persistent<v8::Object> wrapper, WrapperTypeInfo* typeInfo)
    {
        UNUSED_PARAM(object);
        UNUSED_PARAM(wrapper);
        UNUSED_PARAM(typeInfo);
        return false;
    }
};

template<typename T, typename S, v8::WeakReferenceCallback callback>
class GCEpilogueVisitor : public DOMWrapperMap<T>::Visitor {
public:
    void visitDOMWrapper(DOMDataStore* store, T* object, v8::Persistent<v8::Object> wrapper)
    {
        WrapperTypeInfo* typeInfo = V8DOMWrapper::domWrapperType(wrapper);
        if (!S::process(object, wrapper, typeInfo)) {
            ActiveDOMObject* activeDOMObject = typeInfo->toActiveDOMObject(wrapper);
            if (activeDOMObject && activeDOMObject->hasPendingActivity()) {
                ASSERT(!wrapper.IsWeak());
                // NOTE: To re-enable weak status of the active object we use
                // |object| from the map and not |activeDOMObject|. The latter
                // may be a different pointer (in case ActiveDOMObject is not
                // the main base class of the object's class) and pointer
                // identity is required by DOM map functions.
                wrapper.MakeWeak(object, callback);
            }
        }
    }
};

#if PLATFORM(CHROMIUM)
static int workingSetEstimateMB = 0;

static Mutex& workingSetEstimateMBMutex()
{
    AtomicallyInitializedStatic(Mutex&, mutex = *new Mutex);
    return mutex;
}
#endif

void V8GCController::gcEpilogue()
{
    v8::HandleScope scope;

    // Run through all objects with pending activity making their wrappers weak
    // again.
    GCEpilogueVisitor<void, SpecialCaseEpilogueObjectHandler, &DOMDataStore::weakActiveDOMObjectCallback> epilogueObjectVisitor;
    visitActiveDOMObjects(&epilogueObjectVisitor);
    GCEpilogueVisitor<Node, SpecialCaseEpilogueNodeHandler, &DOMDataStore::weakNodeCallback> epilogueNodeVisitor;
    visitActiveDOMNodes(&epilogueNodeVisitor);

#if PLATFORM(CHROMIUM)
    // The GC can happen on multiple threads in case of dedicated workers which run in-process.
    {
        MutexLocker locker(workingSetEstimateMBMutex());
        workingSetEstimateMB = MemoryUsageSupport::actualMemoryUsageMB();
    }
#endif

#ifndef NDEBUG
    EnsureWeakDOMNodeVisitor weakDOMNodeVisitor;
    visitDOMNodes(&weakDOMNodeVisitor);
#endif

    TRACE_EVENT_END0("v8", "GC");
}

void V8GCController::checkMemoryUsage()
{
#if PLATFORM(CHROMIUM)
    const int lowMemoryUsageMB = MemoryUsageSupport::lowMemoryUsageMB();
    const int highMemoryUsageMB = MemoryUsageSupport::highMemoryUsageMB();
    const int highUsageDeltaMB = MemoryUsageSupport::highUsageDeltaMB();
    int memoryUsageMB = MemoryUsageSupport::memoryUsageMB();
    int workingSetEstimateMBCopy;
    {
        MutexLocker locker(workingSetEstimateMBMutex());
        workingSetEstimateMBCopy = workingSetEstimateMB;
    }

    if ((memoryUsageMB > lowMemoryUsageMB && memoryUsageMB > 2 * workingSetEstimateMBCopy) || (memoryUsageMB > highMemoryUsageMB && memoryUsageMB > workingSetEstimateMBCopy + highUsageDeltaMB))
        v8::V8::LowMemoryNotification();
#endif
}

void V8GCController::hintForCollectGarbage()
{
    V8PerIsolateData* data = V8PerIsolateData::current();
    if (!data->shouldCollectGarbageSoon())
        return;
    const int longIdlePauseInMS = 1000;
    data->clearShouldCollectGarbageSoon();
    v8::V8::ContextDisposedNotification();
    v8::V8::IdleNotification(longIdlePauseInMS);
}

void V8GCController::collectGarbage()
{
    v8::HandleScope handleScope;

    ScopedPersistent<v8::Context> context;

    context.adopt(v8::Context::New());
    if (context.isEmpty())
        return;

    {
        v8::Context::Scope scope(context.get());
        v8::Local<v8::String> source = v8::String::New("if (gc) gc();");
        v8::Local<v8::String> name = v8::String::New("gc");
        v8::Handle<v8::Script> script = v8::Script::Compile(source, name);
        if (!script.IsEmpty()) {
            V8RecursionScope::MicrotaskSuppression scope;
            script->Run();
        }
    }

    context.clear();
}

}  // namespace WebCore
