/*
 * Copyright (C) 2011 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"

#if ENABLE(THREADED_SCROLLING)

#import "ScrollingCoordinatorMac.h"

#include "Frame.h"
#include "FrameView.h"
#include "IntRect.h"
#include "Page.h"
#include "PlatformWheelEvent.h"
#include "PluginViewBase.h"
#include "Region.h"
#include "RenderLayerCompositor.h"
#include "RenderView.h"
#include "ScrollAnimator.h"
#include "ScrollingStateScrollingNode.h"
#include "ScrollingStateTree.h"
#include "ScrollingThread.h"
#include "ScrollingTree.h"

#include <wtf/Functional.h>
#include <wtf/MainThread.h>
#include <wtf/PassRefPtr.h>


namespace WebCore {

class ScrollingCoordinatorPrivate {
};

ScrollingCoordinatorMac::ScrollingCoordinatorMac(Page* page)
    : ScrollingCoordinator(page)
    , m_scrollingStateTree(ScrollingStateTree::create())
    , m_scrollingTree(ScrollingTree::create(this))
    , m_scrollingStateTreeCommitterTimer(this, &ScrollingCoordinatorMac::scrollingStateTreeCommitterTimerFired)
{
}

ScrollingCoordinatorMac::~ScrollingCoordinatorMac()
{
    ASSERT(!m_scrollingTree);
}

void ScrollingCoordinatorMac::pageDestroyed()
{
    ScrollingCoordinator::pageDestroyed();

    m_scrollingStateTreeCommitterTimer.stop();

    // Invalidating the scrolling tree will break the reference cycle between the ScrollingCoordinator and ScrollingTree objects.
    ScrollingThread::dispatch(bind(&ScrollingTree::invalidate, m_scrollingTree.release()));
}

ScrollingTree* ScrollingCoordinatorMac::scrollingTree() const
{
    ASSERT(m_scrollingTree);
    return m_scrollingTree.get();
}

void ScrollingCoordinatorMac::commitTreeStateIfNeeded()
{
    if (!m_scrollingStateTree->hasChangedProperties())
        return;

    commitTreeState();
    m_scrollingStateTreeCommitterTimer.stop();
}

void ScrollingCoordinatorMac::frameViewLayoutUpdated(FrameView* frameView)
{
    ASSERT(isMainThread());
    ASSERT(m_page);

    // Compute the region of the page that we can't do fast scrolling for. This currently includes
    // all scrollable areas, such as subframes, overflow divs and list boxes. We need to do this even if the
    // frame view whose layout was updated is not the main frame.
    Region nonFastScrollableRegion = computeNonFastScrollableRegion(m_page->mainFrame(), IntPoint());

    // In the future, we may want to have the ability to set non-fast scrolling regions for more than
    // just the root node. But right now, this concept only applies to the root.
    setNonFastScrollableRegionForNode(nonFastScrollableRegion, m_scrollingStateTree->rootStateNode());

    if (!coordinatesScrollingForFrameView(frameView))
        return;

    ScrollingStateScrollingNode* node = stateNodeForID(frameView->scrollLayerID());
    if (!node)
        return;

    ScrollParameters scrollParameters;
    scrollParameters.horizontalScrollElasticity = frameView->horizontalScrollElasticity();
    scrollParameters.verticalScrollElasticity = frameView->verticalScrollElasticity();
    scrollParameters.hasEnabledHorizontalScrollbar = frameView->horizontalScrollbar() && frameView->horizontalScrollbar()->enabled();
    scrollParameters.hasEnabledVerticalScrollbar = frameView->verticalScrollbar() && frameView->verticalScrollbar()->enabled();
    scrollParameters.horizontalScrollbarMode = frameView->horizontalScrollbarMode();
    scrollParameters.verticalScrollbarMode = frameView->verticalScrollbarMode();

    scrollParameters.scrollOrigin = frameView->scrollOrigin();
    scrollParameters.viewportRect = IntRect(IntPoint(), frameView->visibleContentRect().size());
    scrollParameters.contentsSize = frameView->contentsSize();

    setScrollParametersForNode(scrollParameters, node);
}

void ScrollingCoordinatorMac::recomputeWheelEventHandlerCountForFrameView(FrameView* frameView)
{
    ScrollingStateScrollingNode* node = stateNodeForID(frameView->scrollLayerID());
    if (!node)
        return;
    setWheelEventHandlerCountForNode(computeCurrentWheelEventHandlerCount(), node);
}

void ScrollingCoordinatorMac::frameViewRootLayerDidChange(FrameView* frameView)
{
    ASSERT(isMainThread());
    ASSERT(m_page);

    if (!coordinatesScrollingForFrameView(frameView))
        return;

    // If the root layer does not have a ScrollingStateNode, then we should create one.
    ensureRootStateNodeForFrameView(frameView);
    ASSERT(m_scrollingStateTree->rootStateNode());

    ScrollingCoordinator::frameViewRootLayerDidChange(frameView);

    setScrollLayerForNode(scrollLayerForFrameView(frameView), stateNodeForID(frameView->scrollLayerID()));
}

void ScrollingCoordinatorMac::frameViewHorizontalScrollbarLayerDidChange(FrameView* frameView, GraphicsLayer*)
{
    ASSERT(isMainThread());
    ASSERT(m_page);

    if (frameView->frame() != m_page->mainFrame())
        return;

    // FIXME: Implement.
}

void ScrollingCoordinatorMac::frameViewVerticalScrollbarLayerDidChange(FrameView* frameView, GraphicsLayer*)
{
    ASSERT(isMainThread());
    ASSERT(m_page);
    
    if (frameView->frame() != m_page->mainFrame())
        return;

    // FIXME: Implement.
}

bool ScrollingCoordinatorMac::requestScrollPositionUpdate(FrameView* frameView, const IntPoint& scrollPosition)
{
    ASSERT(isMainThread());
    ASSERT(m_page);

    if (!coordinatesScrollingForFrameView(frameView))
        return false;

    if (frameView->frame()->document()->inPageCache()) {
        // If this frame view's document is being put into the page cache, we don't want to update our
        // main frame scroll position. Just let the FrameView think that we did.
        updateMainFrameScrollPosition(scrollPosition, frameView->inProgrammaticScroll());
        return true;
    }

    ScrollingStateScrollingNode* stateNode = stateNodeForID(frameView->scrollLayerID());
    if (!stateNode)
        return false;

    stateNode->setRequestedScrollPosition(scrollPosition, frameView->inProgrammaticScroll());
    scheduleTreeStateCommit();
    return true;
}

bool ScrollingCoordinatorMac::handleWheelEvent(FrameView*, const PlatformWheelEvent& wheelEvent)
{
    ASSERT(isMainThread());
    ASSERT(m_page);

    if (m_scrollingTree->willWheelEventStartSwipeGesture(wheelEvent))
        return false;

    ScrollingThread::dispatch(bind(&ScrollingTree::handleWheelEvent, m_scrollingTree.get(), wheelEvent));

    return true;
}

void ScrollingCoordinatorMac::updateMainFrameScrollPositionAndScrollLayerPosition()
{
    ASSERT(isMainThread());

    if (!m_page)
        return;

    FrameView* frameView = m_page->mainFrame()->view();
    if (!frameView)
        return;

    IntPoint scrollPosition = m_scrollingTree->mainFrameScrollPosition();

    frameView->setConstrainsScrollingToContentEdge(false);
    frameView->notifyScrollPositionChanged(scrollPosition);
    frameView->setConstrainsScrollingToContentEdge(true);

    if (GraphicsLayer* scrollLayer = scrollLayerForFrameView(frameView))
        scrollLayer->setPosition(-frameView->scrollPosition());
}

ScrollingNodeID ScrollingCoordinatorMac::attachToStateTree(ScrollingNodeID newNodeID, ScrollingNodeID parentID)
{
    ASSERT(newNodeID);

    ScrollingStateScrollingNode* existingNode = stateNodeForID(newNodeID);
    if (existingNode && existingNode == m_scrollingStateTree->rootStateNode())
        return newNodeID;

    // If there is no parent, this is the root node. Right now, we only support the root node.
    // FIXME: In the future, we should append child nodes in the appropriate spot in the state
    // tree.
    if (!parentID) {
        // If we're resetting the root node, we should clear the HashMap and destroy the current children.
        clearStateTree();

        m_scrollingStateTree->rootStateNode()->setScrollingNodeID(newNodeID);
        m_stateNodeMap.set(newNodeID, m_scrollingStateTree->rootStateNode());
    }

    return newNodeID;
}

void ScrollingCoordinatorMac::detachFromStateTree(ScrollingNodeID scrollLayerID)
{
    if (!scrollLayerID)
        return;

    // The node may not be found if clearStateTree() was recently called.
    ScrollingStateNode* node = m_stateNodeMap.take(scrollLayerID);
    if (!node)
        return;

    m_scrollingStateTree->removeNode(node);

    // ScrollingStateTree::removeNode() will destroy children, so we have to make sure we remove those children
    // from the HashMap.
    const Vector<ScrollingNodeID>& removedNodes = m_scrollingStateTree->removedNodes();
    size_t size = removedNodes.size();
    for (size_t i = 0; i < size; ++i)
        m_stateNodeMap.remove(removedNodes[i]);
}

void ScrollingCoordinatorMac::clearStateTree()
{
    m_stateNodeMap.clear();
    m_scrollingStateTree->removeNode(m_scrollingStateTree->rootStateNode());
}

ScrollingStateScrollingNode* ScrollingCoordinatorMac::stateNodeForID(ScrollingNodeID scrollLayerID)
{
    if (!scrollLayerID)
        return 0;

    HashMap<ScrollingNodeID, ScrollingStateNode*>::const_iterator it = m_stateNodeMap.find(scrollLayerID);
    if (it == m_stateNodeMap.end())
        return 0;

    ScrollingStateNode* node = it->value;
    return toScrollingStateScrollingNode(node);
}

void ScrollingCoordinatorMac::ensureRootStateNodeForFrameView(FrameView* frameView)
{
    attachToStateTree(frameView->scrollLayerID(), 0);
}

void ScrollingCoordinatorMac::setScrollLayerForNode(GraphicsLayer* scrollLayer, ScrollingStateNode* node)
{
    node->setScrollLayer(scrollLayer);
    scheduleTreeStateCommit();
}

void ScrollingCoordinatorMac::setNonFastScrollableRegionForNode(const Region& region, ScrollingStateScrollingNode* node)
{
    node->setNonFastScrollableRegion(region);
    scheduleTreeStateCommit();
}

void ScrollingCoordinatorMac::setScrollParametersForNode(const ScrollParameters& scrollParameters, ScrollingStateScrollingNode* node)
{
    node->setHorizontalScrollElasticity(scrollParameters.horizontalScrollElasticity);
    node->setVerticalScrollElasticity(scrollParameters.verticalScrollElasticity);
    node->setHasEnabledHorizontalScrollbar(scrollParameters.hasEnabledHorizontalScrollbar);
    node->setHasEnabledVerticalScrollbar(scrollParameters.hasEnabledVerticalScrollbar);
    node->setHorizontalScrollbarMode(scrollParameters.horizontalScrollbarMode);
    node->setVerticalScrollbarMode(scrollParameters.verticalScrollbarMode);

    node->setScrollOrigin(scrollParameters.scrollOrigin);
    node->setViewportRect(scrollParameters.viewportRect);
    node->setContentsSize(scrollParameters.contentsSize);
    scheduleTreeStateCommit();
}

void ScrollingCoordinatorMac::setWheelEventHandlerCountForNode(unsigned wheelEventHandlerCount, ScrollingStateScrollingNode* node)
{
    node->setWheelEventHandlerCount(wheelEventHandlerCount);
    scheduleTreeStateCommit();
}

void ScrollingCoordinatorMac::setShouldUpdateScrollLayerPositionOnMainThread(MainThreadScrollingReasons reasons)
{
    // The FrameView's GraphicsLayer is likely to be out-of-synch with the PlatformLayer
    // at this point. So we'll update it before we switch back to main thread scrolling
    // in order to avoid layer positioning bugs.
    if (reasons)
        updateMainFrameScrollLayerPosition();
    m_scrollingStateTree->rootStateNode()->setShouldUpdateScrollLayerPositionOnMainThread(reasons);
    scheduleTreeStateCommit();
}

void ScrollingCoordinatorMac::updateMainFrameScrollLayerPosition()
{
    ASSERT(isMainThread());

    if (!m_page)
        return;

    FrameView* frameView = m_page->mainFrame()->view();
    if (!frameView)
        return;

    if (GraphicsLayer* scrollLayer = scrollLayerForFrameView(frameView))
        scrollLayer->setPosition(-frameView->scrollPosition());
}

void ScrollingCoordinatorMac::scheduleTreeStateCommit()
{
    if (m_scrollingStateTreeCommitterTimer.isActive())
        return;

    if (!m_scrollingStateTree->hasChangedProperties())
        return;

    m_scrollingStateTreeCommitterTimer.startOneShot(0);
}

void ScrollingCoordinatorMac::scrollingStateTreeCommitterTimerFired(Timer<ScrollingCoordinatorMac>*)
{
    commitTreeState();
}

void ScrollingCoordinatorMac::commitTreeState()
{
    ASSERT(m_scrollingStateTree->hasChangedProperties());

    OwnPtr<ScrollingStateTree> treeState = m_scrollingStateTree->commit();
    ScrollingThread::dispatch(bind(&ScrollingTree::commitNewTreeState, m_scrollingTree.get(), treeState.release()));
}

} // namespace WebCore

#endif // ENABLE(THREADED_SCROLLING)
